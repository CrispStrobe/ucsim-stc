/*
 * Simulator of microcontrollers (s51.src/ucstc12.cc)
 *
 * STC12C5A60S2 model
 *
 * 1T 8052-based MCU with:
 *   - AUXR.7/AUXR.6 timer 1T/12T select
 *   - Port mode registers (PxM1/PxM0) for quasi-bidir/push-pull/input/open-drain
 *   - 10-bit ADC on P1
 *   - 2-channel PCA/PWM (using existing ucsim PCA infrastructure)
 *   - No Timer 2 (the T2CON address 0xC8 is P5 on STC12)
 *   - P4 at 0xC0, P5 at 0xC8
 *
 * Copyright (C) 2024 CrispStrobe
 *
 */

#include "ucstc12cl.h"
#include "regs51.h"

#include "stc12_timercl.h"
#include "stc12_adccl.h"
#include "stc12_portcl.h"
#include "portcl.h"
#include "stc12_pcacl.h"
#include "serialcl.h"
#include "dregcl.h"
#include "port_hwcl.h"
#include "interruptcl.h"


cl_uc_stc12::cl_uc_stc12(struct cpu_entry *Itype, class cl_sim *asim):
  cl_uc52(Itype, asim)
{
}

int
cl_uc_stc12::init(void)
{
  int ret= cl_uc52::init();
  return ret;
}

const char *
cl_uc_stc12::id_string(void)
{
  return "STC12C5A60S2";
}

void
cl_uc_stc12::mk_hw_elements(void)
{
  class cl_hw *h;

  /* Call cl_51core's base (NOT cl_uc52's, which adds Timer 2).
     The STC12 has no Timer 2; its address (0xC8) is P5. */
  cl_uc::mk_hw_elements();

  acc= sfr->get_cell(ACC);
  psw= sfr->get_cell(PSW);

  /* STC12 timers with AUXR.7/AUXR.6 1T mode support */
  h= new cl_timer0_stc12(this, 0, "timer0");
  h->init();
  add_hw(h);
  h= new cl_timer0_stc12(this, 1, "timer1");
  h->init();
  add_hw(h);

  /* Serial port (standard 8051 UART) */
  h= new cl_serial(this);
  h->init();
  add_hw(h);

  /* Debug display */
  add_hw(h= new cl_dreg(this, 0, "dreg"));
  h->init();

  /* Port display */
  class cl_port_ui *d;
  add_hw(d= new cl_port_ui(this, 0, "dport"));
  d->init();

  /* Standard ports P0-P3 */
  class cl_port *p0, *p1, *p2, *p3;
  add_hw(p0= new cl_port(this, 0));
  p0->init();
  add_hw(p1= new cl_port(this, 1));
  p1->init();
  add_hw(p2= new cl_port(this, 2));
  p2->init();
  add_hw(p3= new cl_port(this, 3));
  p3->init();

  /* Port display data */
  class cl_port_data pd;
  pd.init();
  pd.cell_dir= NULL;

  pd.set_name("P0");
  pd.cell_p  = p0->cell_p;
  pd.cell_in = p0->cell_in;
  pd.keyset  = keysets[0];
  pd.basx    = 1;
  pd.basy    = 5;
  d->add_port(&pd, 0);

  pd.set_name("P1");
  pd.cell_p  = p1->cell_p;
  pd.cell_in = p1->cell_in;
  pd.keyset  = keysets[1];
  pd.basx    = 20;
  pd.basy    = 5;
  d->add_port(&pd, 1);

  pd.set_name("P2");
  pd.cell_p  = p2->cell_p;
  pd.cell_in = p2->cell_in;
  pd.keyset  = keysets[2];
  pd.basx    = 40;
  pd.basy    = 5;
  d->add_port(&pd, 2);

  pd.set_name("P3");
  pd.cell_p  = p3->cell_p;
  pd.cell_in = p3->cell_in;
  pd.keyset  = keysets[3];
  pd.basx    = 60;
  pd.basy    = 5;
  d->add_port(&pd, 3);

  /* Interrupt system */
  add_hw(interrupt= new cl_interrupt(this));
  interrupt->init();

  /* STC12-specific port mode registers for P0-P5 */
  for (int i= 0; i < 6; i++)
    {
      h= new cl_stc12_port_mode(this, i);
      h->init();
      add_hw(h);
    }

  /* ADC */
  h= new cl_stc12_adc(this);
  h->init();
  add_hw(h);

  /* PCA with 2 modules and correct 1T clock prescaling */
  h= new cl_pca_stc12(this, 0);
  h->init();
  add_hw(h);
}

void
cl_uc_stc12::make_memories(void)
{
  cl_uc52::make_memories();
}

void
cl_uc_stc12::make_chips(void)
{
  /* STC12C5A60S2: 60KB flash, 256B IRAM, 1280B XRAM.
     Keep 64K ROM and 64K XRAM address spaces from base for compatibility;
     code images simply don't fill the full space. */
  cl_51core::make_chips();
}

void
cl_uc_stc12::decode_sfr(void)
{
  cl_51core::decode_sfr();
}

void
cl_uc_stc12::make_vars(void)
{
  cl_51core::make_vars();
}

void
cl_uc_stc12::clear_sfr(void)
{
  /* Call cl_51core's clear, NOT cl_uc52's (which writes T2CON etc.) */
  cl_51core::clear_sfr();

  /* STC12-specific SFR reset values */
  sfr->write(AUXR,  0x00);  /* 12T mode for both timers */
  sfr->write(STC12_P0M1, 0x00);
  sfr->write(STC12_P0M0, 0x00);
  sfr->write(STC12_P1M1, 0x00);
  sfr->write(STC12_P1M0, 0x00);
  sfr->write(STC12_P2M1, 0x00);
  sfr->write(STC12_P2M0, 0x00);
  sfr->write(STC12_P3M1, 0x00);
  sfr->write(STC12_P3M0, 0x00);
  sfr->write(STC12_P4M1, 0x00);
  sfr->write(STC12_P4M0, 0x00);
  sfr->write(STC12_P5M1, 0x00);
  sfr->write(STC12_P5M0, 0x00);
  sfr->write(STC12_CLK_DIV, 0x00);
  sfr->write(STC12_P1ASF, 0x00);
  sfr->write(STC12_P4SW, 0x00);
  sfr->write(STC12_ADC_CONTR, 0x00);
  sfr->write(STC12_ADC_RES,  0x00);
  sfr->write(STC12_ADC_RESL, 0x00);
  sfr->write(STC12_P4, 0xff);  /* ports reset high */
  sfr->write(STC12_P5, 0xff);
  /* PCA registers */
  sfr->write(CCON,  0x00);
  sfr->write(CMOD,  0x00);
  sfr->write(CCAPM0, 0x00);
  sfr->write(CCAPM1, 0x00);
  sfr->write(CL,    0x00);
  sfr->write(CH,    0x00);
  sfr->write(CCAP0H, 0x00);
  sfr->write(CCAP1H, 0x00);
  sfr->write(STC12_PCA_PWM0, 0x00);
  sfr->write(STC12_PCA_PWM1, 0x00);
}


/* End of s51.src/ucstc12.cc */
