/*
 * Simulator of microcontrollers (s51.src/stc12_wdtcl.h)
 *
 * STC12C5A60S2 watchdog timer (WDT_CONTR at 0xC1)
 *
 * Copyright (C) 2026 CrispStrobe
 */

#ifndef STC12_WDTCL_HEADER
#define STC12_WDTCL_HEADER

#include "stypes.h"
#include "pobjcl.h"
#include "uccl.h"

#define STC12_WDT_CONTR  0xC1
#define WDT_EN_WDT       0x20
#define WDT_CLR_WDT      0x10
#define WDT_IDLE_WDT     0x08
#define WDT_PS_MASK      0x07
#define WDT_FLAG          0x80

class cl_stc12_wdt: public cl_hw
{
protected:
  class cl_memory_cell *cell_wdt_contr;
  unsigned int prescaler_cnt;
  unsigned int counter;
public:
  cl_stc12_wdt(class cl_uc *auc);
  virtual int init(void);
  virtual void write(class cl_memory_cell *cell, t_mem *val);
  virtual int tick(int cycles);
  virtual void print_info(class cl_console_base *con);
};

#endif
