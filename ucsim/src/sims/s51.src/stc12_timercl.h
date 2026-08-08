/*
 * Simulator of microcontrollers (s51.src/stc12_timercl.h)
 *
 * STC12 Timer with AUXR.7/AUXR.6 1T mode support
 *
 * Copyright (C) 2024 CrispStrobe
 *
 */

#ifndef STC12_TIMERCL_HEADER
#define STC12_TIMERCL_HEADER

#include "timer0cl.h"

class cl_timer0_stc12: public cl_timer0
{
protected:
  class cl_memory_cell *cell_auxr;
  t_mem auxr_1t_mask; /* 0x80 for timer0, 0x40 for timer1 */
  int prescaler;      /* counts up to 12 for 12T mode */
public:
  cl_timer0_stc12(class cl_uc *auc, int aid, const char *aid_string);
  virtual int init(void);
  virtual int tick(int cycles);
};


#endif

/* End of s51.src/stc12_timercl.h */
