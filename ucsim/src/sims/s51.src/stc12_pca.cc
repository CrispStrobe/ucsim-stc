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
 * Copyright (C) 2026 CrispStrobe
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

  /* Read all 3 CPS bits from CMOD (§5.2).
     The base class only tracks CPS1:CPS0; we need CPS2 too. */
  t_mem cmod_val= cell_cmod ? cell_cmod->get() : 0;
  int cps= (cmod_val >> 1) & 0x07; /* CPS2:CPS1:CPS0 */

  switch (cps)
    {
    case 0: /* SYSclk/12 */
      pca_prescaler += cycles;
      { int eff= pca_prescaler / 12; pca_prescaler %= 12;
	if (eff > 0) do_pca_counter(eff); }
      break;
    case 1: /* SYSclk/2 */
      pca_prescaler += cycles;
      { int eff= pca_prescaler / 2; pca_prescaler %= 2;
	if (eff > 0) do_pca_counter(eff); }
      break;
    case 2: /* Timer 0 overflow */
      do_pca_counter(t0_overflows);
      t0_overflows= 0;
      break;
    case 3: /* ECI pin */
      do_pca_counter(ECI_edge);
      ECI_edge= 0;
      break;
    case 4: /* SYSclk (1:1, no prescaler) */
      do_pca_counter(cycles);
      break;
    case 5: /* SYSclk/4 */
      pca_prescaler += cycles;
      { int eff= pca_prescaler / 4; pca_prescaler %= 4;
	if (eff > 0) do_pca_counter(eff); }
      break;
    case 6: /* SYSclk/6 */
      pca_prescaler += cycles;
      { int eff= pca_prescaler / 6; pca_prescaler %= 6;
	if (eff > 0) do_pca_counter(eff); }
      break;
    case 7: /* SYSclk/8 */
      pca_prescaler += cycles;
      { int eff= pca_prescaler / 8; pca_prescaler %= 8;
	if (eff > 0) do_pca_counter(eff); }
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
	    /* PCA_PWMn addresses for the 9th bit (EPCnL) */
	    static const t_addr pwm_addrs[] = {0xF2, 0xF3, 0xF4};
	    for (int i= 0; i < n_modules; i++)
	      {
		if ((ccapm[i] & bmECOM) && (ccapm[i] & bmPWM))
		  {
		    /* 9-bit compare: {EPCnL,CCAPnL} vs {0,CL} (§5.3) */
		    t_mem epcl= (i < 3) ? (s->get(pwm_addrs[i]) & 0x01) : 0;
		    unsigned compare= (epcl << 8) | cell_ccapl[i]->get();
		    if ((unsigned)cl_val < compare)
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
