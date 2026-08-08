/*
 * Simulator of microcontrollers (s51.src/stc12_adc.cc)
 *
 * STC12C5A60S2 ADC peripheral
 *
 * The ADC is 10-bit, 8-channel (P1.0-P1.7).
 * P1ASF selects which P1 pins have analog function.
 * ADC_CONTR controls power, start, speed, and channel.
 * ADC_FLAG (bit 4 of ADC_CONTR) is set by hardware on completion
 * and must be cleared by software.
 * Result is in ADC_RES (high 8) and ADC_RESL (low 2, bits 1:0).
 *
 * NOTE: This model returns synthetic ADC values (mid-scale by default).
 * It has NOT been validated on silicon.  It verifies the register
 * sequence is self-consistent, which is useful for software testing.
 *
 * Copyright (C) 2024 CrispStrobe
 *
 */

#include <stdio.h>

#include "stc12_adccl.h"
#include "regs51.h"


cl_stc12_adc::cl_stc12_adc(class cl_uc *auc):
  cl_hw(auc, HW_TIMER /* reuse category */, 10, "stc12_adc")
{
  conversion_delay= 0;
  adc_channel= 0;
  adc_powered= false;
}

int
cl_stc12_adc::init(void)
{
  cl_hw::init();

  class cl_address_space *sfr= uc->address_space(MEM_SFR_ID);
  if (sfr)
    {
      cell_adc_contr= register_cell(sfr, STC12_ADC_CONTR);
      cell_adc_res  = sfr->get_cell(STC12_ADC_RES);
      cell_adc_resl = sfr->get_cell(STC12_ADC_RESL);
      cell_p1asf    = sfr->get_cell(STC12_P1ASF);
    }
  return 0;
}

void
cl_stc12_adc::write(class cl_memory_cell *cell, t_mem *val)
{
  if (cell == cell_adc_contr)
    {
      t_mem v= *val;
      adc_powered= (v & bmADC_POWER) != 0;

      if ((v & bmADC_START) && adc_powered)
	{
	  /* Start conversion.
	     Speed bits (6:5) select conversion time:
	       00 = 420 clocks, 01 = 280, 10 = 140, 11 = 70
	     We approximate these as tick counts. */
	  int speed= (v & bmADC_SPEED) >> 5;
	  static const int delays[] = { 420, 280, 140, 70 };
	  conversion_delay= delays[speed];
	  adc_channel= v & bmADC_CHS;

	  /* Clear START bit in the value being written (hardware behavior) */
	  *val= v & ~bmADC_START;
	}

      /* If software is clearing ADC_FLAG, let it through */
    }
}

int
cl_stc12_adc::tick(int cycles)
{
  if (conversion_delay > 0)
    {
      conversion_delay -= cycles;
      if (conversion_delay <= 0)
	{
	  conversion_delay= 0;

	  /* Conversion complete.  Generate a synthetic result.
	     Use mid-scale (0x200 = 512) as default.
	     A more sophisticated model could read from a config or
	     respond to external stimulus. */
	  t_mem p1asf= cell_p1asf->get();
	  u16_t result= 0x200; /* mid-scale default */

	  if (!(p1asf & (1 << adc_channel)))
	    {
	      /* Channel not enabled as analog in P1ASF.
		 Real hardware behavior is undefined; return 0. */
	      result= 0;
	    }

	  /* Store 10-bit result: high 8 in ADC_RES, low 2 in ADC_RESL[1:0] */
	  cell_adc_res->set(result >> 2);
	  cell_adc_resl->set(result & 0x03);

	  /* Set ADC_FLAG */
	  cell_adc_contr->set(cell_adc_contr->get() | bmADC_FLAG);
	}
    }
  return resGO;
}

void
cl_stc12_adc::print_info(class cl_console_base *con)
{
  t_mem contr= cell_adc_contr->get();
  con->dd_printf("STC12 ADC: %s", adc_powered ? "ON" : "OFF");
  con->dd_printf(" ch=%d", contr & bmADC_CHS);
  con->dd_printf(" flag=%c", (contr & bmADC_FLAG) ? '1' : '0');
  con->dd_printf(" result=0x%03x",
		 (cell_adc_res->get() << 2) | (cell_adc_resl->get() & 0x03));
  con->dd_printf(" P1ASF=0x%02x", cell_p1asf->get());
  if (conversion_delay > 0)
    con->dd_printf(" converting(%d ticks left)", conversion_delay);
  con->dd_printf("\n");
}


/* End of s51.src/stc12_adc.cc */
