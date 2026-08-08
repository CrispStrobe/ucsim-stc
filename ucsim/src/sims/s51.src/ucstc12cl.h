/*
 * Simulator of microcontrollers (s51.src/ucstc12cl.h)
 *
 * STC12C5A60S2 model
 *
 * Copyright (C) 2024 CrispStrobe
 *
 */

/* This file is part of microcontroller simulator: ucsim.

UCSIM is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

UCSIM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with UCSIM; see the file COPYING.  If not, write to the Free
Software Foundation, 59 Temple Place - Suite 330, Boston, MA
02111-1307, USA. */

#ifndef UCSTC12CL_HEADER
#define UCSTC12CL_HEADER

#include "uc52cl.h"

class cl_uc_stc12: public cl_uc52
{
public:
  cl_uc_stc12(struct cpu_entry *Itype, class cl_sim *asim);
  virtual int init(void);
  virtual const char *id_string(void);
  virtual int clock_per_cycle(void) { return(1); }
  virtual void mk_hw_elements(void);
  virtual void make_memories(void);
  virtual void make_chips(void);
  virtual void decode_sfr(void);
  virtual void make_vars(void);
  virtual void clear_sfr(void);
};


#endif

/* End of s51.src/ucstc12cl.h */
