/*
 * Simulator of microcontrollers (s51.src/stc12_wdt.cc)
 *
 * STC12C5A60S2 watchdog timer
 *
 * WDT_CONTR (0xC1):
 *   bit 7: WDT_FLAG (set on overflow, cleared by software)
 *   bit 5: EN_WDT (enable, once set cannot be cleared except by reset)
 *   bit 4: CLR_WDT (write 1 to clear/restart, auto-clears)
 *   bit 3: IDLE_WDT (count in idle mode)
 *   bits 2:0: PS (prescaler select, period = 12M * 32768 * 2^(PS+1) / FOSC)
 *
 * Counter overflows at 32768 → sets WDT_FLAG.
 * In a real chip this resets the CPU; in the emulator we just set the flag.
 *
 * Copyright (C) 2026 CrispStrobe
 */

#include <stdio.h>
#include "stc12_wdtcl.h"


cl_stc12_wdt::cl_stc12_wdt(class cl_uc *auc):
  cl_hw(auc, HW_TIMER, 11, "stc12_wdt")
{
  prescaler_cnt= 0;
  counter= 0;
}

int
cl_stc12_wdt::init(void)
{
  cl_hw::init();
  class cl_address_space *sfr= uc->address_space(MEM_SFR_ID);
  if (sfr)
    cell_wdt_contr= register_cell(sfr, STC12_WDT_CONTR);
  return 0;
}

void
cl_stc12_wdt::write(class cl_memory_cell *cell, t_mem *val)
{
  if (cell == cell_wdt_contr)
    {
      if (*val & WDT_CLR_WDT)
	{
	  /* Clear/restart the watchdog counter */
	  counter= 0;
	  prescaler_cnt= 0;
	  *val &= ~WDT_CLR_WDT; /* auto-clear the CLR bit */
	}
    }
}

int
cl_stc12_wdt::tick(int cycles)
{
  t_mem wdt= cell_wdt_contr->get();
  if (!(wdt & WDT_EN_WDT))
    return resGO;

  /* Idle mode: only count if IDLE_WDT is set */
  if (uc->state == stIDLE && !(wdt & WDT_IDLE_WDT))
    return resGO;

  int ps= wdt & WDT_PS_MASK;
  unsigned int divisor= 2u << ps; /* 2^(ps+1) */

  prescaler_cnt += cycles;
  while (prescaler_cnt >= divisor)
    {
      prescaler_cnt -= divisor;
      counter++;
      if (counter >= 32768)
	{
	  /* Watchdog overflow — set flag.
	     A real chip resets here. */
	  cell_wdt_contr->set(cell_wdt_contr->get() | WDT_FLAG);
	  counter= 0;
	}
    }
  return resGO;
}

void
cl_stc12_wdt::print_info(class cl_console_base *con)
{
  t_mem wdt= cell_wdt_contr->get();
  con->dd_printf("STC12 WDT: %s", (wdt & WDT_EN_WDT) ? "ON" : "OFF");
  con->dd_printf(" PS=%d", wdt & WDT_PS_MASK);
  con->dd_printf(" counter=%u/32768", counter);
  con->dd_printf(" flag=%c", (wdt & WDT_FLAG) ? '1' : '0');
  con->dd_printf("\n");
}
