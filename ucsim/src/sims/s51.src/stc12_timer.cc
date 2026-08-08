/*
 * Simulator of microcontrollers (s51.src/stc12_timer.cc)
 *
 * STC12 Timer with AUXR.7/AUXR.6 1T mode support
 *
 * In the STC12C5A60S2, the CPU is a 1T architecture (clock_per_cycle=1).
 * Timers default to 12T mode (AUXR.7=0 for T0, AUXR.6=0 for T1),
 * counting at FOSC/12.  Setting the AUXR bit switches to 1T (FOSC).
 *
 * Since hw->tick() is called once per machine cycle (= 1 osc clock on
 * this 1T CPU), 12T mode needs a prescaler that fires every 12th tick.
 *
 * Copyright (C) 2026 CrispStrobe
 *
 */

#include "stc12_timercl.h"
#include "regs51.h"


cl_timer0_stc12::cl_timer0_stc12(class cl_uc *auc, int aid,
				 const char *aid_string):
  cl_timer0(auc, aid, aid_string)
{
  cell_auxr= 0;
  prescaler= 0;
  auxr_1t_mask= (aid == 0) ? bmAUXR_T0x12 : bmAUXR_T1x12;
}

int
cl_timer0_stc12::init(void)
{
  int ret= cl_timer0::init();

  class cl_address_space *sfr= uc->address_space(MEM_SFR_ID);
  if (sfr)
    cell_auxr= register_cell(sfr, AUXR);

  return ret;
}

int
cl_timer0_stc12::tick(int cycles)
{
  bool one_t= cell_auxr && (cell_auxr->get() & auxr_1t_mask);

  if (one_t)
    {
      /* 1T mode: timer counts at FOSC, once per osc clock.
	 tick() is called once per osc clock, so pass through directly. */
      return cl_timer0::tick(cycles);
    }
  else
    {
      /* 12T mode (default): timer counts at FOSC/12.
	 Accumulate osc clocks in prescaler, fire base tick every 12th. */
      prescaler += cycles;
      int effective= prescaler / 12;
      prescaler %= 12;
      if (effective > 0)
	return cl_timer0::tick(effective);
      return resGO;
    }
}


/* End of s51.src/stc12_timer.cc */
