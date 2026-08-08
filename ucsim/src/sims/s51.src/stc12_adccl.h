/*
 * Simulator of microcontrollers (s51.src/stc12_adccl.h)
 *
 * STC12C5A60S2 ADC peripheral
 *
 * Copyright (C) 2024 CrispStrobe
 *
 */

#ifndef STC12_ADCCL_HEADER
#define STC12_ADCCL_HEADER

#include "stypes.h"
#include "pobjcl.h"
#include "uccl.h"

class cl_stc12_adc: public cl_hw
{
protected:
  class cl_memory_cell *cell_adc_contr;
  class cl_memory_cell *cell_adc_res;
  class cl_memory_cell *cell_adc_resl;
  class cl_memory_cell *cell_p1asf;
  int conversion_delay;  /* ticks remaining until conversion complete */
  int adc_channel;
  bool adc_powered;
public:
  cl_stc12_adc(class cl_uc *auc);
  virtual int init(void);
  virtual void write(class cl_memory_cell *cell, t_mem *val);
  virtual int tick(int cycles);
  virtual void print_info(class cl_console_base *con);
};


#endif

/* End of s51.src/stc12_adccl.h */
