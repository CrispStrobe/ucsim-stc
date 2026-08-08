/*
 * Simulator of microcontrollers (s51.src/stc12_portcl.h)
 *
 * STC12C5A60S2 port mode support (PxM1/PxM0)
 *
 * Copyright (C) 2024 CrispStrobe
 *
 */

#ifndef STC12_PORTCL_HEADER
#define STC12_PORTCL_HEADER

#include "stypes.h"
#include "pobjcl.h"
#include "uccl.h"

/*
 * Port mode configuration hardware.
 * Watches PxM1/PxM0 writes and updates port behavior:
 *   M1:M0 = 00 quasi-bidirectional (default, standard 8051)
 *   M1:M0 = 01 push-pull output
 *   M1:M0 = 10 input-only (high impedance)
 *   M1:M0 = 11 open-drain
 */
class cl_stc12_port_mode: public cl_hw
{
protected:
  int port_id;  /* 0-5 for P0-P5 */
  class cl_memory_cell *cell_pxm1;
  class cl_memory_cell *cell_pxm0;
  class cl_memory_cell *cell_port;
  t_addr addr_pxm1, addr_pxm0, addr_port;
public:
  cl_stc12_port_mode(class cl_uc *auc, int port_nr);
  virtual int init(void);
  virtual void write(class cl_memory_cell *cell, t_mem *val);
  virtual void print_info(class cl_console_base *con);
};


#endif

/* End of s51.src/stc12_portcl.h */
