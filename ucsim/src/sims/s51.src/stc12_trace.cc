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

  /* Scan for our flags before passing to ucsim's init.
     ucsim ignores unknown flags gracefully. */
  for (int i= 1; i < argc; i++)
    {
      if (strcmp(argv[i], "-fosc") == 0 && i + 1 < argc)
	{ fosc= strtoul(argv[i+1], NULL, 0); have_fosc= true; }
      else if (strcmp(argv[i], "-until-ns") == 0 && i + 1 < argc)
	{ until_ns= strtoull(argv[i+1], NULL, 0); have_until= true; }
    }

  /* Strip our flags from argv so ucsim doesn't choke on them */
  int new_argc= 0;
  char **new_argv= (char**)malloc(argc * sizeof(char*));
  for (int i= 0; i < argc; i++)
    {
      if ((strcmp(argv[i], "-fosc") == 0 ||
	   strcmp(argv[i], "-until-ns") == 0) && i + 1 < argc)
	{ i++; continue; } /* skip flag and its value */
      new_argv[new_argc++]= argv[i];
    }

  /* Force -t STC12 if not already specified */
  bool has_type= false;
  for (int i= 0; i < new_argc; i++)
    if (strcmp(new_argv[i], "-t") == 0) has_type= true;

  if (!has_type)
    {
      new_argv= (char**)realloc(new_argv, (new_argc + 3) * sizeof(char*));
      /* Insert -t STC12 before the hex file (last positional arg) */
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

  /* Enable trace to stdout */
  uc->trace_start(stdout, fosc, until_ns);

  /* Run until the time limit */
  for (;;)
    {
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
