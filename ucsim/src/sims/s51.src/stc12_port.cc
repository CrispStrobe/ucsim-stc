/*
 * Simulator of microcontrollers (s51.src/stc12_port.cc)
 *
 * STC12C5A60S2 port mode configuration (PxM1/PxM0)
 *
 * Port modes per pin (M1:M0):
 *   00 = quasi-bidirectional (default, standard 8051)
 *   01 = push-pull output
 *   10 = input-only (high impedance)
 *   11 = open-drain
 *
 * This module watches writes to PxM1/PxM0 registers and records
 * the mode.  The actual electrical behavior change (drive strength,
 * input impedance) is modeled as metadata; the port data register
 * read/write still works through the base cl_port class.
 *
 * Copyright (C) 2026 CrispStrobe
 *
 */

#include <stdio.h>

#include "stc12_portcl.h"
#include "regs51.h"


/* SFR addresses for PxM1/PxM0, indexed by port number */
static const t_addr pxm1_addrs[] = {
  STC12_P0M1, STC12_P1M1, STC12_P2M1, STC12_P3M1, STC12_P4M1, STC12_P5M1
};
static const t_addr pxm0_addrs[] = {
  STC12_P0M0, STC12_P1M0, STC12_P2M0, STC12_P3M0, STC12_P4M0, STC12_P5M0
};
static const t_addr port_addrs[] = {
  P0, P1, P2, P3, STC12_P4, STC12_P5
};


cl_stc12_port_mode::cl_stc12_port_mode(class cl_uc *auc, int port_nr):
  cl_hw(auc, HW_PORT, 10 + port_nr, "stc12_portmode")
{
  port_id= port_nr;
  cell_pxm1= cell_pxm0= cell_port= 0;
  addr_pxm1= pxm1_addrs[port_nr];
  addr_pxm0= pxm0_addrs[port_nr];
  addr_port= port_addrs[port_nr];
}

int
cl_stc12_port_mode::init(void)
{
  cl_hw::init();

  class cl_address_space *sfr= uc->address_space(MEM_SFR_ID);
  if (sfr)
    {
      cell_pxm1= register_cell(sfr, addr_pxm1);
      cell_pxm0= register_cell(sfr, addr_pxm0);
      cell_port= sfr->get_cell(addr_port);
    }
  return 0;
}

void
cl_stc12_port_mode::write(class cl_memory_cell *cell, t_mem *val)
{
  /* Just accept the write.  The mode bits are stored in the SFR cells
     and can be queried via print_info.  Actual electrical behavior
     differences (input-only blocking writes, open-drain needing
     external pull-up) would need deeper integration with the port
     hardware model. */
}

void
cl_stc12_port_mode::print_info(class cl_console_base *con)
{
  static const char *mode_names[] = {
    "quasi-bidir", "push-pull", "input-only", "open-drain"
  };

  t_mem m1= cell_pxm1 ? cell_pxm1->get() : 0;
  t_mem m0= cell_pxm0 ? cell_pxm0->get() : 0;

  con->dd_printf("P%d port modes (PxM1=0x%02x PxM0=0x%02x):\n",
		 port_id, m1, m0);
  for (int bit= 7; bit >= 0; bit--)
    {
      int mode= ((m1 >> bit) & 1) << 1 | ((m0 >> bit) & 1);
      con->dd_printf("  P%d.%d: %s\n", port_id, bit, mode_names[mode]);
    }
}


/* End of s51.src/stc12_port.cc */
