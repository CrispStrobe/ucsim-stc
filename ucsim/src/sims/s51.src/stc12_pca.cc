/*
 * Simulator of microcontrollers (s51.src/stc12_pca.cc)
 *
 * STC12 PCA with correct clock prescaling for 1T CPU.
 *
 * On the STC12 (1T CPU, clock_per_cycle=1), hw->tick() is called once
 * per oscillator clock.  The PCA clock sources need adjustment:
 *
 *   CPS1:CPS0=00  FOSC/12  ->  prescale by 12
 *   CPS1:CPS0=01  FOSC/2   ->  prescale by 2
 *   CPS1:CPS0=10  Timer 0 overflow  ->  unchanged (event-driven)
 *   CPS1:CPS0=11  ECI pin  ->  unchanged (event-driven)
 *
 * Copyright (C) 2024 CrispStrobe
 *
 */

#include "stc12_pcacl.h"
#include "regs51.h"


cl_pca_stc12::cl_pca_stc12(class cl_uc *auc, int aid, int modules):
  cl_pca(auc, aid)
{
  pca_prescaler= 0;
  n_modules= modules;
}

int
cl_pca_stc12::tick(int cycles)
{
  if (!bit_CR)
    return(resGO);
  if (uc->state == stIDLE && bit_CIDL)
    return(resGO);

  switch (clk_source)
    {
    case 0:
      /* FOSC/12: on 1T CPU, divide ticks by 12 */
      pca_prescaler += cycles;
      {
	int eff= pca_prescaler / 12;
	pca_prescaler %= 12;
	if (eff > 0)
	  do_pca_counter(eff);
      }
      break;
    case bmCPS0:
      /* FOSC/2: on 1T CPU, divide ticks by 2 */
      pca_prescaler += cycles;
      {
	int eff= pca_prescaler / 2;
	pca_prescaler %= 2;
	if (eff > 0)
	  do_pca_counter(eff);
      }
      break;
    case bmCPS1:
      /* Timer 0 overflow: event-driven, same as base */
      do_pca_counter(t0_overflows);
      t0_overflows= 0;
      break;
    case (bmCPS0|bmCPS1):
      /* ECI pin: event-driven, same as base */
      do_pca_counter(ECI_edge);
      ECI_edge= 0;
      break;
    }
  return(resGO);
}


void
cl_pca_stc12::do_pca_counter(int cycles)
{
  /* STC12 has 2 PCA modules, STC15 has 3. The base 8052 has 5.
     PWM output is computed on every CL tick (§5.3). Compare/match
     and capture are only checked on overflow. */
  while (cycles--)
    {
      t_mem cl_val= cell_cl->set(cell_cl->get() + 1);

      /* PWM output: compare CL vs CCAPnL on every tick.
	 Only write P1 when the output actually changes. */
      {
	class cl_address_space *s= uc->address_space(MEM_SFR_ID);
	if (s)
	  {
	    t_mem p1_old= s->get(0x90);
	    t_mem p1_new= p1_old;
	    static const u8_t cex_mask[] = {0x08, 0x10, 0x20, 0x40, 0x80};
	    for (int i= 0; i < n_modules; i++)
	      {
		if ((ccapm[i] & bmECOM) && (ccapm[i] & bmPWM))
		  {
		    if (cl_val < cell_ccapl[i]->get())
		      p1_new &= ~cex_mask[i]; /* LOW */
		    else
		      p1_new |= cex_mask[i];  /* HIGH */
		  }
	      }
	    if (p1_new != p1_old)
	      s->set(0x90, p1_new);
	  }
      }

      if (cl_val == 0)
	{
	  /* CL wrapped: reload CCAPnL from CCAPnH for PWM modules */
	  for (int i= 0; i < n_modules; i++)
	    if (ccapm[i] & bmPWM)
	      cell_ccapl[i]->set(cell_ccaph[i]->get());

	  if (cell_ch->set(cell_ch->get() + 1) == 0)
	    {
	      /* Full CH:CL overflow */
	      cell_ccon->set(cell_ccon->get() | bmCF);
	      for (int i= 0; i < n_modules; i++)
		do_pca_module(i);
	    }
	}
    }
}


/* End of s51.src/stc12_pca.cc */
