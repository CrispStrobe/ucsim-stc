/*
 * Simulator of microcontrollers (s51.src/stc15_timer2cl.h)
 *
 * STC15 Timer 2: 16-bit auto-reload at T2H/T2L (0xD6/0xD7).
 * Controlled by AUXR bits 4 (T2R), 2 (T2x12).
 * Used as UART1 baud rate generator when AUXR.S1ST2 = 1.
 *
 * Copyright (C) 2026 CrispStrobe
 */

#ifndef STC15_TIMER2CL_HEADER
#define STC15_TIMER2CL_HEADER

#include "stypes.h"
#include "pobjcl.h"
#include "uccl.h"

class cl_timer2_stc15: public cl_hw
{
protected:
  class cl_memory_cell *cell_auxr;
  class cl_memory_cell *cell_t2l;
  class cl_memory_cell *cell_t2h;
  int prescaler;
  unsigned char reload_h, reload_l; /* captured on T2R rising edge */
public:
  cl_timer2_stc15(class cl_uc *auc);
  virtual int init(void);
  virtual int tick(int cycles);
  virtual void print_info(class cl_console_base *con);
};

#endif
