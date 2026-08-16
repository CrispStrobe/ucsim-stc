/*
 * Simulator of microcontrollers (s51.src/ucstc12cl.h)
 *
 * STC12C5A60S2 model
 *
 * Copyright (C) 2026 CrispStrobe
 *
 */

/* This file is part of microcontroller simulator: ucsim.

UCSIM is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

UCSIM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with UCSIM; see the file COPYING.  If not, write to the Free
Software Foundation, 59 Temple Place - Suite 330, Boston, MA
02111-1307, USA. */

#ifndef UCSTC12CL_HEADER
#define UCSTC12CL_HEADER

#include <stdio.h>

#include "uc52cl.h"

/* Part identity */
#define STC_PART_STC12  0
#define STC_PART_STC15  1
#define STC_PART_STC89  2
#define STC_PART_STC15W 3

/* SFR watch list for differential trace (matches spec) */
#define STC12_TRACE_NWATCH 24

/* Debug target: yield breakpoint */
#define STC12_MAX_TASKS 8
#define STC12_MAX_YIELD_BPS 32

struct stc12_task_info {
  const char *name;
  t_addr state_addr;   /* IRAM address of <task>_state */
  t_addr until_addr;   /* IRAM address of <task>_until */
  t_addr func_addr;    /* code address of function entry */
};

struct stc12_yield_bp {
  bool active;
  int task_idx;        /* index into task_info */
  unsigned int state;  /* the state number to break on */
  t_addr code_addr;    /* code address of the case label */
};

class cl_uc_stc12: public cl_uc52
{
protected:
  /* Trace state */
  FILE *trace_file;
  unsigned long long trace_osc_clocks;
  unsigned long long trace_until_ns;
  unsigned long trace_fosc;
  t_mem trace_sfr_shadow[STC12_TRACE_NWATCH];
  t_addr trace_sfr_addrs[STC12_TRACE_NWATCH];
  t_addr trace_last_pc;
  t_mem trace_full_sfr_shadow[128]; /* full SFR range for unmodelled detection */
  bool trace_unmodelled_reported[128]; /* report each unmodelled addr once */
  void trace_check_sfr(void);

  /* Part identity */
  int stc_part;  /* STC_PART_STC12 or STC_PART_STC15 */

  /* Debug target state */
  t_addr bw_ms_addr;          /* IRAM address of bw_ms (0 = not set) */
  int n_tasks;
  struct stc12_task_info task_info[STC12_MAX_TASKS];
  int n_yield_bps;
  struct stc12_yield_bp yield_bps[STC12_MAX_YIELD_BPS];

public:
  cl_uc_stc12(struct cpu_entry *Itype, class cl_sim *asim);
  virtual int init(void);
  virtual const char *id_string(void);
  virtual int clock_per_cycle(void) { return (stc_part == STC_PART_STC89) ? 12 : 1; }
  virtual void mk_hw_elements(void);
  virtual void make_memories(void);
  virtual void make_chips(void);
  virtual void decode_sfr(void);
  virtual void make_vars(void);
  virtual void clear_sfr(void);
  virtual int do_inst(void);
  virtual int tick_hw(int cycles);

  /* Trace API */
  void trace_start(FILE *f, unsigned long fosc, unsigned long long until_ns);
  unsigned long long trace_time_ns(void) { return trace_osc_clocks * 1000000000ULL / trace_fosc; }

  /* Debug target API (boundary D §7) */
  void debug_set_bw_ms(t_addr iram_addr);
  void debug_add_task(const char *name, t_addr state_addr,
		      t_addr until_addr, t_addr func_addr);
  int debug_add_yield_bp(int task_idx, unsigned int state, t_addr code_addr);

  /* Level 1 position (§2): read task state from IRAM */
  unsigned int debug_read_bw_ms(void);
  unsigned int debug_read_task_state(int task_idx);
  unsigned int debug_read_task_until(int task_idx);

  /* Step N instructions, return final PC */
  t_addr debug_step_insn(int count);
};


#endif

/* End of s51.src/ucstc12cl.h */
