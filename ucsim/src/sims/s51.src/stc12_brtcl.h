/*
 * STC12 BRT (Baud Rate Timer) — 8-bit auto-reload at FOSC or FOSC/12.
 *
 * Overflows feed the serial port's baud clock when AUXR.S1BRS=1.
 * On the STC15, Timer 2 does this job instead (AUXR.S1ST2=1) and
 * the BRT is deprecated.
 *
 * Copyright (C) 2026 CrispStrobe
 * GPL-2.0-or-later
 */

#ifndef STC12_BRTCL_HEADER
#define STC12_BRTCL_HEADER

#include "hwcl.h"

class cl_stc12_brt: public cl_hw
{
protected:
  class cl_memory_cell *cell_brt;     /* BRT reload register (0x9C) */
  class cl_memory_cell *cell_auxr;    /* AUXR (0x8E) */
  int prescaler;                       /* counts to 12 for FOSC/12 mode */
  unsigned char counter;               /* 8-bit counter */
public:
  cl_stc12_brt(class cl_uc *auc);
  virtual int init(void);
  virtual int tick(int cycles);
  virtual void print_info(class cl_console_base *con);
};

#endif
