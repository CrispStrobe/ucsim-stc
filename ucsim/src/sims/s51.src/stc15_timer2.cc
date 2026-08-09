/*
 * Simulator of microcontrollers (s51.src/stc15_timer2.cc)
 *
 * STC15 Timer 2: 16-bit auto-reload timer.
 *
 * T2H/T2L (0xD6/0xD7) serve as both counter and reload register.
 * AUXR.4 (T2R) = run, AUXR.2 (T2x12) = 1T/12T.
 * On overflow, T2H/T2L auto-reload from themselves (the value
 * present at the overflow moment is the reload value for the
 * next period — software writes the new period into T2H/T2L
 * while the timer is running).
 *
 * Per STC15-PERIPHERAL-MODEL.md §2.2 and §3.
 *
 * Copyright (C) 2026 CrispStrobe
 */

#include <stdio.h>
#include "stc15_timer2cl.h"
#include "regs51.h"


cl_timer2_stc15::cl_timer2_stc15(class cl_uc *auc):
  cl_hw(auc, HW_TIMER, 12, "stc15_timer2")
{
  prescaler= 0;
}

int
cl_timer2_stc15::init(void)
{
  cl_hw::init();
  class cl_address_space *sfr= uc->address_space(MEM_SFR_ID);
  if (sfr)
    {
      cell_auxr= register_cell(sfr, AUXR);
      cell_t2l= sfr->get_cell(STC15_T2L);
      cell_t2h= sfr->get_cell(STC15_T2H);
    }
  return 0;
}

int
cl_timer2_stc15::tick(int cycles)
{
  if (!cell_auxr)
    return resGO;

  t_mem auxr= cell_auxr->get();

  /* T2R (bit 4) = run control */
  if (!(auxr & bmAUXR_T2R))
    return resGO;

  /* T2x12 (bit 2) selects 1T or 12T */
  bool one_t= (auxr & bmAUXR_T2x12) != 0;

  if (one_t)
    {
      /* 1T: count at FOSC, one tick per osc clock */
      /* Fall through — count 'cycles' directly */
    }
  else
    {
      /* 12T: prescale by 12 */
      prescaler += cycles;
      cycles= prescaler / 12;
      prescaler %= 12;
      if (cycles == 0)
	return resGO;
    }

  while (cycles--)
    {
      /* 16-bit increment */
      t_mem tl= cell_t2l->get();
      t_mem th= cell_t2h->get();
      unsigned int val= (th << 8) | tl;
      val++;
      if (val > 0xFFFF)
	{
	  /* Overflow: auto-reload.
	     T2H/T2L auto-reload from themselves — the current
	     values ARE the reload value. On overflow, the counter
	     wraps to 0 and the next period starts from whatever
	     software wrote to T2H/T2L. */
	  val= 0; /* wrap to 0 (reload is T2H/T2L's current value) */
	}
      cell_t2l->set(val & 0xFF);
      cell_t2h->set((val >> 8) & 0xFF);
    }

  return resGO;
}

void
cl_timer2_stc15::print_info(class cl_console_base *con)
{
  t_mem auxr= cell_auxr ? cell_auxr->get() : 0;
  bool running= (auxr & bmAUXR_T2R) != 0;
  bool one_t= (auxr & bmAUXR_T2x12) != 0;
  unsigned int val= (cell_t2h->get() << 8) | cell_t2l->get();

  con->dd_printf("STC15 Timer2: %s", running ? "ON" : "OFF");
  con->dd_printf(" %s", one_t ? "1T" : "12T");
  con->dd_printf(" T2H:T2L=0x%04X", val);
  con->dd_printf("\n");
}
