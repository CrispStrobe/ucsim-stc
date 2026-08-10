/*
 * stc12_trace.cc — headless differential execution trace emitter.
 *
 * Same init sequence as s51.cc, but instead of the interactive command
 * loop, runs a trace loop that emits per-instruction SFR/TF/ADC events.
 *
 * Usage: stc12_trace [-t STC12] [-fosc Hz] [-until-ns N] firmware.hex
 *
 * Copyright (C) 2026 CrispStrobe
 * GPL-2.0-or-later
 */

#include "globals.h"
#include "utils.h"
#include "sim51cl.h"
#include "ucstc12cl.h"
#include "serialcl.h"
#include "portcl.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>


int
main(int argc, char *argv[])
{
  unsigned long fosc= 11059200;
  unsigned long long until_ns= 2000000;
  bool have_fosc= false, have_until= false;

  /* -inject TIME_NS,BYTE — schedule a byte delivery to the UART RX.
   *
   * Multiple -inject flags are allowed; they are processed in order.
   * At the specified simulated time (nanoseconds), the byte is made
   * available to the serial model's RX path. The serial model then
   * counts bit periods (using the BRT/T2 baud clock) before raising
   * RI, so the byte arrives at the firmware at TIME_NS plus one
   * frame time (~87 µs at 115200).
   *
   * WHAT THIS MODELS: byte delivery at a scheduled point in simulated
   * time, with the serial model's own bit-period counting for the
   * RI delay.
   *
   * WHAT THIS DOES NOT MODEL: wire-level start/stop/parity bits,
   * baud-rate mismatch detection, or electrical signal levels. An
   * injected byte always arrives intact regardless of the baud
   * configuration — a wrong divisor will not corrupt it. The
   * idle-timeout resync path IS reachable (the gap between injections
   * is real simulated time), but baud errors are not.
   *
   * Usage: stc12_trace -inject 0,0x7E -inject 87000,0x03 ... firmware.hex
   */
#define MAX_INJECT 64
  struct { unsigned long long time_ns; unsigned char byte; } inject[MAX_INJECT];
  int n_inject= 0;
  int inject_next= 0;

  /* Scan for our flags before passing to ucsim's init.
     ucsim ignores unknown flags gracefully. */
  for (int i= 1; i < argc; i++)
    {
      if (strcmp(argv[i], "-fosc") == 0 && i + 1 < argc)
	{ fosc= strtoul(argv[i+1], NULL, 0); have_fosc= true; }
      else if (strcmp(argv[i], "-until-ns") == 0 && i + 1 < argc)
	{ until_ns= strtoull(argv[i+1], NULL, 0); have_until= true; }
      else if (strcmp(argv[i], "-inject") == 0 && i + 1 < argc)
	{
	  unsigned long long t;
	  unsigned int b;
	  if (sscanf(argv[++i], "%llu,%i", &t, &b) == 2 && n_inject < MAX_INJECT)
	    {
	      inject[n_inject].time_ns= t;
	      inject[n_inject].byte= (unsigned char)b;
	      n_inject++;
	    }
	}
    }

  /* Strip our flags from argv so ucsim doesn't choke on them */
  int new_argc= 0;
  char **new_argv= (char**)malloc(argc * sizeof(char*));
  for (int i= 0; i < argc; i++)
    {
      if ((strcmp(argv[i], "-fosc") == 0 ||
	   strcmp(argv[i], "-until-ns") == 0 ||
	   strcmp(argv[i], "-inject") == 0) && i + 1 < argc)
	{ i++; continue; } /* skip flag and its value */
      new_argv[new_argc++]= argv[i];
    }

  /* Force -t STC12 if not already specified.
     Accepted: STC12, STC15, STC89, STC15W (and full part names). */
  bool has_type= false;
  for (int i= 0; i < new_argc; i++)
    if (strcmp(new_argv[i], "-t") == 0) has_type= true;

  if (!has_type)
    {
      new_argv= (char**)realloc(new_argv, (new_argc + 3) * sizeof(char*));
      new_argv[new_argc]= (char*)"-t";
      new_argv[new_argc+1]= (char*)"STC12";
      new_argc += 2;
    }
  new_argv[new_argc]= NULL;

  /* Standard ucsim init — redirect stdout to stderr during init
     so the banner doesn't pollute the trace stream. */
  app_start_at= dnow();
  cpus= cpus_51;
  int saved_stdout= dup(1);
  dup2(2, 1); /* stdout -> stderr */
  application= new cl_app();
  application->set_name("stc12_trace");
  application->init(new_argc, new_argv);

  class cl_sim *sim= new cl_sim51(application);
  if (sim->init())
    {
      fprintf(stderr, "Failed to initialize simulator\n");
      return 1;
    }
  application->set_simulator(sim);

  /* Get the STC12 UC */
  class cl_uc *uc_base= sim->get_uc();
  if (!uc_base)
    {
      fprintf(stderr, "No microcontroller created\n");
      return 1;
    }

  class cl_uc_stc12 *uc= dynamic_cast<cl_uc_stc12*>(uc_base);
  if (!uc)
    {
      fprintf(stderr, "Not an STC12 model (use -t STC12)\n");
      return 1;
    }

  /* Load hex files that were passed as positional args.
     application->init() stored them in in_files. */
  for (int i= 0; i < sim->app->in_files->count; i++)
    {
      const char *fname= (const char *)(sim->app->in_files->at(i));
      long l;
      if ((l= uc->read_hex_file(fname)) >= 0)
	fprintf(stderr, "%ld words read from %s\n", l, fname);
      else
	fprintf(stderr, "Failed to load %s\n", fname);
    }

  /* Restore stdout for trace output */
  dup2(saved_stdout, 1);
  close(saved_stdout);

  /* Disable stop-on-selfjump — cooperative schedulers loop
     repeatedly without PC changing. */
  uc->stop_selfjump= false;

  /* Find the serial hw for byte injection */
  class cl_serial *serial_hw= NULL;
  if (n_inject > 0)
    {
      class cl_hw *hw= uc->get_hw(HW_UART, 0, 0);
      serial_hw= dynamic_cast<class cl_serial *>(hw);
      if (!serial_hw)
	fprintf(stderr, "Warning: -inject requires UART hw (not found)\n");
    }

  /* Enable trace to stdout */
  uc->trace_start(stdout, fosc, until_ns);

  /* Run until the time limit */
  for (;;)
    {
      /* Inject bytes at their scheduled times */
      if (serial_hw && inject_next < n_inject)
	{
	  unsigned long long t_ns= uc->trace_time_ns();
	  while (inject_next < n_inject && t_ns >= inject[inject_next].time_ns)
	    {
	      serial_hw->inject_byte(inject[inject_next].byte);
	      fprintf(stderr, "inject: %llu ns byte 0x%02X\n",
		      (unsigned long long)inject[inject_next].time_ns,
		      (unsigned)inject[inject_next].byte);
	      inject_next++;
	    }
	}

      int res= uc->do_inst();
      /* resSTOP from our do_inst override means time limit reached.
	 Everything else (resGO, resSELFJUMP, etc.) means keep going. */
      if (res == resSTOP)
	break;
    }

  free(new_argv);
  application->done();
  delete application;
  return 0;
}
