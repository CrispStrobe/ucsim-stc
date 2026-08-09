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
 * Copyright (C) 2026 CrispStrobe
 *
 */

#include "ucstc12cl.h"
#include "regs51.h"

#include "stc12_timercl.h"
#include "stc12_adccl.h"
#include "stc12_portcl.h"
#include "stc12_wdtcl.h"
#include "stc15_timer2cl.h"
#include "portcl.h"
#include "stc12_pcacl.h"
#include "serialcl.h"
#include "dregcl.h"
#include "port_hwcl.h"
#include "interruptcl.h"


/* MCS-51 instruction cycle table — REMOVED.
 *
 * This array was transcribed from Intel MCS-51 Table A-2 and used as
 * a tick_tab override. It was REMOVED because the base ucsim instruction
 * handlers already call tick(N) internally for multi-cycle instructions,
 * and providing a tick_tab on top of that caused double-counting (25%
 * timing gap). See spec-updates/005-emu8051-cycle-count-bug.md.
 *
 * Timing now comes from the base MCS-51 handlers in jmp.cc, bit.cc,
 * arith.cc, etc. The residual 1-clock gap against emu8051 is from minor
 * differences in how interrupt dispatch ticks are counted.
 */

#if 0 /* Dead code — retained for reference only, not compiled */
static i8_t stc12_cycle_tab[256] = {
  /* 0x00 NOP    */ 1,
  /* 0x01 AJMP   */ 2,
  /* 0x02 LJMP   */ 2,
  /* 0x03 RR     */ 1,
  /* 0x04 INC A  */ 1,
  /* 0x05 INC d  */ 1,
  /* 0x06 INC @R0*/ 1,
  /* 0x07 INC @R1*/ 1,
  /* 0x08-0x0F INC Rn */ 1,1,1,1,1,1,1,1,
  /* 0x10 JBC    */ 2,
  /* 0x11 ACALL  */ 2,
  /* 0x12 LCALL  */ 2,
  /* 0x13 RRC    */ 1,
  /* 0x14 DEC A  */ 1,
  /* 0x15 DEC d  */ 1,
  /* 0x16 DEC @R0*/ 1,
  /* 0x17 DEC @R1*/ 1,
  /* 0x18-0x1F DEC Rn */ 1,1,1,1,1,1,1,1,
  /* 0x20 JB     */ 2,
  /* 0x21 AJMP   */ 2,
  /* 0x22 RET    */ 2,
  /* 0x23 RL     */ 1,
  /* 0x24 ADD #  */ 1,
  /* 0x25 ADD d  */ 1,
  /* 0x26 ADD @R0*/ 1,
  /* 0x27 ADD @R1*/ 1,
  /* 0x28-0x2F ADD Rn */ 1,1,1,1,1,1,1,1,
  /* 0x30 JNB    */ 2,
  /* 0x31 ACALL  */ 2,
  /* 0x32 RETI   */ 2,
  /* 0x33 RLC    */ 1,
  /* 0x34 ADDC # */ 1,
  /* 0x35 ADDC d */ 1,
  /* 0x36 ADDC@R0*/ 1,
  /* 0x37 ADDC@R1*/ 1,
  /* 0x38-0x3F ADDC Rn */ 1,1,1,1,1,1,1,1,
  /* 0x40 JC     */ 2,
  /* 0x41 AJMP   */ 2,
  /* 0x42 ORL d,A*/ 1,
  /* 0x43 ORL d,#*/ 2,
  /* 0x44 ORL A,#*/ 1,
  /* 0x45 ORL A,d*/ 1,
  /* 0x46 ORL@R0 */ 1,
  /* 0x47 ORL@R1 */ 1,
  /* 0x48-0x4F ORL A,Rn */ 1,1,1,1,1,1,1,1,
  /* 0x50 JNC    */ 2,
  /* 0x51 ACALL  */ 2,
  /* 0x52 ANL d,A*/ 1,
  /* 0x53 ANL d,#*/ 2,
  /* 0x54 ANL A,#*/ 1,
  /* 0x55 ANL A,d*/ 1,
  /* 0x56 ANL@R0 */ 1,
  /* 0x57 ANL@R1 */ 1,
  /* 0x58-0x5F ANL A,Rn */ 1,1,1,1,1,1,1,1,
  /* 0x60 JZ     */ 2,
  /* 0x61 AJMP   */ 2,
  /* 0x62 XRL d,A*/ 1,
  /* 0x63 XRL d,#*/ 2,
  /* 0x64 XRL A,#*/ 1,
  /* 0x65 XRL A,d*/ 1,
  /* 0x66 XRL@R0 */ 1,
  /* 0x67 XRL@R1 */ 1,
  /* 0x68-0x6F XRL A,Rn */ 1,1,1,1,1,1,1,1,
  /* 0x70 JNZ    */ 2,
  /* 0x71 ACALL  */ 2,
  /* 0x72 ORL C,b*/ 2,
  /* 0x73 JMP@A+D*/ 2,
  /* 0x74 MOV A,#*/ 1,
  /* 0x75 MOV d,#*/ 2,
  /* 0x76 MOV@R0#*/ 1,
  /* 0x77 MOV@R1#*/ 1,
  /* 0x78-0x7F MOV Rn,# */ 1,1,1,1,1,1,1,1,
  /* 0x80 SJMP   */ 2,
  /* 0x81 AJMP   */ 2,
  /* 0x82 ANL C,b*/ 2,
  /* 0x83 MOVC PC*/ 2,
  /* 0x84 DIV    */ 4,
  /* 0x85 MOV d,d*/ 2,
  /* 0x86 MOV d,@*/ 2,
  /* 0x87 MOV d,@*/ 2,
  /* 0x88-0x8F MOV d,Rn */ 2,2,2,2,2,2,2,2,
  /* 0x90 MOV DPT*/ 2,
  /* 0x91 ACALL  */ 2,
  /* 0x92 MOV b,C*/ 2,
  /* 0x93 MOVC DP*/ 2,
  /* 0x94 SUBB # */ 1,
  /* 0x95 SUBB d */ 1,
  /* 0x96 SUBB@R0*/ 1,
  /* 0x97 SUBB@R1*/ 1,
  /* 0x98-0x9F SUBB Rn */ 1,1,1,1,1,1,1,1,
  /* 0xA0 ORL C/b*/ 2,
  /* 0xA1 AJMP   */ 2,
  /* 0xA2 MOV C,b*/ 1,
  /* 0xA3 INC DPT*/ 2,
  /* 0xA4 MUL    */ 4,
  /* 0xA5 (undef)*/ 1,
  /* 0xA6 MOV@R0d*/ 2,
  /* 0xA7 MOV@R1d*/ 2,
  /* 0xA8-0xAF MOV Rn,d */ 2,2,2,2,2,2,2,2,
  /* 0xB0 ANL C/b*/ 2,
  /* 0xB1 ACALL  */ 2,
  /* 0xB2 CPL bit*/ 1,
  /* 0xB3 CPL C  */ 1,
  /* 0xB4 CJNE#  */ 2,
  /* 0xB5 CJNE d */ 2,
  /* 0xB6 CJNE@0#*/ 2,
  /* 0xB7 CJNE@1#*/ 2,
  /* 0xB8-0xBF CJNE Rn,# */ 2,2,2,2,2,2,2,2,
  /* 0xC0 PUSH   */ 2,
  /* 0xC1 AJMP   */ 2,
  /* 0xC2 CLR bit*/ 1,
  /* 0xC3 CLR C  */ 1,
  /* 0xC4 SWAP   */ 1,
  /* 0xC5 XCH d  */ 1,
  /* 0xC6 XCH@R0 */ 1,
  /* 0xC7 XCH@R1 */ 1,
  /* 0xC8-0xCF XCH Rn */ 1,1,1,1,1,1,1,1,
  /* 0xD0 POP    */ 2,
  /* 0xD1 ACALL  */ 2,
  /* 0xD2 SETB b */ 1,
  /* 0xD3 SETB C */ 1,
  /* 0xD4 DA     */ 1,
  /* 0xD5 DJNZ d */ 2,
  /* 0xD6 XCHD@R0*/ 1,
  /* 0xD7 XCHD@R1*/ 1,
  /* 0xD8-0xDF DJNZ Rn */ 2,2,2,2,2,2,2,2,
  /* 0xE0 MOVX DP*/ 2,
  /* 0xE1 AJMP   */ 2,
  /* 0xE2 MOVX@R0*/ 2,
  /* 0xE3 MOVX@R1*/ 2,
  /* 0xE4 CLR A  */ 1,
  /* 0xE5 MOV A,d*/ 1,
  /* 0xE6 MOV A@R0*/ 1,
  /* 0xE7 MOV A@R1*/ 1,
  /* 0xE8-0xEF MOV A,Rn */ 1,1,1,1,1,1,1,1,
  /* 0xF0 MOVX@DP*/ 2,
  /* 0xF1 ACALL  */ 2,
  /* 0xF2 MOVX@R0*/ 2,
  /* 0xF3 MOVX@R1*/ 2,
  /* 0xF4 CPL A  */ 1,
  /* 0xF5 MOV d,A*/ 1,
  /* 0xF6 MOV@R0A*/ 1,
  /* 0xF7 MOV@R1A*/ 1,
  /* 0xF8-0xFF MOV Rn,A */ 1,1,1,1,1,1,1,1,
};
#endif /* Dead cycle table */

/* STC12C5A60S2 defined SFR addresses.
 * Any SFR write outside this set is an unmodelled register access. */
static bool stc12_sfr_defined[128]; /* indexed by addr - 0x80 */
static bool stc12_sfr_defined_init = false;
static void init_sfr_defined(void)
{
  if (stc12_sfr_defined_init) return;
  memset(stc12_sfr_defined, 0, sizeof(stc12_sfr_defined));
  static const t_addr defined[] = {
    0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, /* P0,SP,DPL,DPH,DPL1,DPH1,DPS,PCON */
    0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D,    /* TCON, TMOD, TL0, TL1, TH0, TH1 */
    0x8E,                                    /* AUXR */
    0x8F,                                    /* WAKE_CLKO (clock output control) */
    0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, /* P1, PxM, CLK_DIV */
    0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D,    /* SCON, SBUF, S2CON, S2BUF, BRT, P1ASF */
    0xA0, 0xA2, 0xA8, 0xA9,                /* P2, AUXR1, IE, SADDR */
    0xB0, 0xB1, 0xB2, 0xB3, 0xB4,          /* P3, P3M1, P3M0, P4M1, P4M0 */
    0xB6, 0xB7,                              /* IP2H, IPH */
    0xB8, 0xB9, 0xBB, 0xBC, 0xBD, 0xBE,   /* IP, SADEN, P4SW, ADC_CONTR/RES/RESL */
    0xC1,                                    /* WDT_CONTR */
    0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7,   /* IAP: DATA, ADDRH, ADDRL, CMD, TRIG, CONTR */
    0xC0, 0xC8, 0xC9, 0xCA,                /* P4, P5, P5M1, P5M0 */
    0xD0, 0xD8, 0xD9, 0xDA, 0xDB,          /* PSW, CCON, CMOD, CCAPM0, CCAPM1 */
    0xE0, 0xE9, 0xEA, 0xEB,                  /* ACC, CL, CCAP0L, CCAP1L */
    0xF0, 0xF2, 0xF3, 0xF9, 0xFA, 0xFB,   /* B, PCA_PWM0/1, CH, CCAP0H, CCAP1H */
  };
  for (unsigned i= 0; i < sizeof(defined)/sizeof(defined[0]); i++)
    stc12_sfr_defined[defined[i] - 0x80]= true;
  stc12_sfr_defined_init= true;
}

/* Additional SFRs defined on STC15 (delta from STC12) */
static void init_sfr_defined_stc15(void)
{
  init_sfr_defined(); /* start with STC12 base */
  static const t_addr stc15_extra[] = {
    0x8F,   /* INT_CLKO / AUXR2 */
    0xA1,   /* BUS_SPEED */
    0xAA,   /* WKTCL (wake-up timer low) */
    0xAB,   /* WKTCH (wake-up timer high) */
    0xBA,   /* P_SW2 */
    0xCD,   /* SPSTAT */
    0xCE,   /* SPCTL */
    0xCF,   /* SPDAT */
    0xD6,   /* T2H */
    0xD7,   /* T2L */
    0xDC,   /* CCAPM2 */
    0xEC,   /* CCAP2L */
    0xF4,   /* PCA_PWM2 */
    0xFC,   /* CCAP2H */
  };
  for (unsigned i= 0; i < sizeof(stc15_extra)/sizeof(stc15_extra[0]); i++)
    stc12_sfr_defined[stc15_extra[i] - 0x80]= true;
}

/* STC89C52RC: standard 8052 SFR set only — no port modes, no ADC, no PCA */
static bool stc89_sfr_defined[128];
static bool stc89_sfr_defined_init = false;
static void init_sfr_defined_stc89(void)
{
  if (stc89_sfr_defined_init) return;
  memset(stc89_sfr_defined, 0, sizeof(stc89_sfr_defined));
  static const t_addr defined[] = {
    0x80, 0x81, 0x82, 0x83, 0x87,           /* P0, SP, DPL, DPH, PCON */
    0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D,     /* TCON, TMOD, TL0, TL1, TH0, TH1 */
    0x90,                                     /* P1 */
    0x98, 0x99,                               /* SCON, SBUF */
    0xA0, 0xA8, 0xA9,                        /* P2, IE, SADDR */
    0xB0, 0xB8, 0xB9,                        /* P3, IP, SADEN */
    0xC8, 0xCA, 0xCB, 0xCC, 0xCD,           /* T2CON, RCAP2L, RCAP2H, TL2, TH2 */
    0xD0,                                     /* PSW */
    0xE0, 0xE1,                               /* ACC, WDT_CONTR */
    0xE2, 0xE3, 0xE4, 0xE5,                  /* ISP_DATA, ISP_ADDRH, ISP_ADDRL, ISP_CMD */
    0xE6, 0xE7,                               /* ISP_TRIG, ISP_CONTR */
    0xF0,                                     /* B */
  };
  for (unsigned i= 0; i < sizeof(defined)/sizeof(defined[0]); i++)
    stc89_sfr_defined[defined[i] - 0x80]= true;
  stc89_sfr_defined_init= true;
}

/* STC15W408AS: STC15 minus Timer 1, minus P4/P5, minus UART2 */
static void init_sfr_defined_stc15w(void)
{
  init_sfr_defined_stc15(); /* start with STC15F base */
  /* Remove P4, P5, P4M1, P4M0, P5M1, P5M0, P4SW (already gone on STC15) */
  stc12_sfr_defined[0xC0 - 0x80]= false; /* P4 */
  stc12_sfr_defined[0xC8 - 0x80]= false; /* P5 */
  stc12_sfr_defined[0xC9 - 0x80]= false; /* P5M1 */
  stc12_sfr_defined[0xCA - 0x80]= false; /* P5M0 */
  stc12_sfr_defined[0xB3 - 0x80]= false; /* P4M1 */
  stc12_sfr_defined[0xB4 - 0x80]= false; /* P4M0 */
  /* Timer 1 SFRs stay in the map (cells exist) but have no timer effect.
     The 8052 core needs TH1/TL1 for the UART baud rate when Timer 1 is
     used, and we keep the cells to avoid crashing on reads.  The timer
     hardware itself is simply not instantiated. */
}

/* SFR watch list matching the trace format spec */
static const t_addr stc12_watch_addrs[STC12_TRACE_NWATCH] = {
  0x80, /* P0 */
  0x88, /* TCON */
  0x89, /* TMOD */
  0x8E, /* AUXR */
  0x90, /* P1 */
  0x91, /* P1M1 */
  0x92, /* P1M0 */
  0x93, /* P0M1 */
  0x94, /* P0M0 */
  0x95, /* P2M1 */
  0x96, /* P2M0 */
  0xA0, /* P2 */
  0xB0, /* P3 */
  0xB1, /* P3M1 */
  0xB2, /* P3M0 */
  0xBC, /* ADC_CONTR */
  0xC0, /* P4 */
  0xD8, /* CCON */
  0xD9, /* CMOD */
  0xDA, /* CCAPM0 */
  0xDB, /* CCAPM1 */
};


cl_uc_stc12::cl_uc_stc12(struct cpu_entry *Itype, class cl_sim *asim):
  cl_uc52(Itype, asim)
{
  int sub= Itype->subtype & 0x30;
  if (sub == 0x20)
    stc_part= STC_PART_STC89;
  else if (sub == 0x30)
    stc_part= STC_PART_STC15W;
  else if (sub == 0x10)
    stc_part= STC_PART_STC15;
  else
    stc_part= STC_PART_STC12;

  if (stc_part == STC_PART_STC89)
    init_sfr_defined_stc89();
  else if (stc_part == STC_PART_STC15W)
    init_sfr_defined_stc15w();
  else if (stc_part == STC_PART_STC15)
    init_sfr_defined_stc15();
  else
    init_sfr_defined();
  memset(trace_full_sfr_shadow, 0, sizeof(trace_full_sfr_shadow));
  memset(trace_unmodelled_reported, 0, sizeof(trace_unmodelled_reported));
  trace_file= NULL;
  trace_osc_clocks= 0;
  trace_until_ns= 0;
  trace_fosc= 11059200;
  trace_last_pc= 0xFFFF;
  bw_ms_addr= 0;
  n_tasks= 0;
  n_yield_bps= 0;
  for (int i= 0; i < STC12_TRACE_NWATCH; i++)
    {
      trace_sfr_addrs[i]= stc12_watch_addrs[i];
      trace_sfr_shadow[i]= 0;
    }
}

int
cl_uc_stc12::init(void)
{
  int ret= cl_uc52::init();

  /* Dual DPTR: present on STC12 and STC15 variants, absent on STC89 */
  if (stc_part != STC_PART_STC89)
    {
      cpu->cfg_set(uc51cpu_aof_mdps, 0x86);   /* DPS address */
      cpu->cfg_set(uc51cpu_mask_mdps, 1);      /* bit 0 */
      cpu->cfg_set(uc51cpu_aof_mdps1l, 0x84);  /* DPL1 */
      cpu->cfg_set(uc51cpu_aof_mdps1h, 0x85);  /* DPH1 */
      cpu->cfg_set(uc51cpu_mdp_mode, 's');     /* SFR mode */
      decode_dptr();
    }

  return ret;
}

const char *
cl_uc_stc12::id_string(void)
{
  switch (stc_part)
    {
    case STC_PART_STC15:  return "STC15F2K60S2";
    case STC_PART_STC89:  return "STC89C52RC";
    case STC_PART_STC15W: return "STC15W408AS";
    default:              return "STC12C5A60S2";
    }
}

void
cl_uc_stc12::mk_hw_elements(void)
{
  class cl_hw *h;

  bool is_stc89= (stc_part == STC_PART_STC89);
  bool has_timer1= (stc_part != STC_PART_STC15W);
  bool has_port_modes= !is_stc89;
  bool has_adc= !is_stc89;
  bool has_pca= !is_stc89;
  bool has_timer2= (stc_part == STC_PART_STC15 || stc_part == STC_PART_STC15W);
  bool has_p4p5= (stc_part == STC_PART_STC12 || stc_part == STC_PART_STC15);
  int port_mode_count= has_p4p5 ? 6 : 4; /* P0-P5 or P0-P3 */

  if (is_stc89)
    {
      /* STC89: standard 8052 hardware — call cl_uc52's mk_hw_elements
	 which sets up standard timers (12T), Timer 2, serial, ports,
	 interrupts, and display. */
      cl_uc52::mk_hw_elements();
      return;
    }

  /* STC12/STC15/STC15W: 1T core with STC peripherals.
     Call cl_uc's base (NOT cl_uc52's, which adds Timer 2 at 0xC8).
     On STC12 the T2CON address (0xC8) is P5; on STC15 variants,
     Timer 2 is at 0xD6/0xD7 instead. */
  cl_uc::mk_hw_elements();

  acc= sfr->get_cell(ACC);
  psw= sfr->get_cell(PSW);

  /* Timers with AUXR.7/AUXR.6 1T mode support */
  h= new cl_timer0_stc12(this, 0, "timer0");
  h->init();
  add_hw(h);
  if (has_timer1)
    {
      h= new cl_timer0_stc12(this, 1, "timer1");
      h->init();
      add_hw(h);
    }

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

  /* Port mode registers (P0-P3 or P0-P5 depending on part) */
  if (has_port_modes)
    {
      for (int i= 0; i < port_mode_count; i++)
	{
	  h= new cl_stc12_port_mode(this, i);
	  h->init();
	  add_hw(h);
	}
    }

  /* ADC */
  if (has_adc)
    {
      h= new cl_stc12_adc(this, stc_part);
      h->init();
      add_hw(h);
    }

  /* Watchdog timer */
  h= new cl_stc12_wdt(this);
  h->init();
  add_hw(h);

  /* Timer 2 (STC15 variants only) */
  if (has_timer2)
    {
      h= new cl_timer2_stc15(this);
      h->init();
      add_hw(h);
    }

  /* PCA with correct module count and 1T clock prescaling */
  if (has_pca)
    {
      int pca_modules= (stc_part == STC_PART_STC15 || stc_part == STC_PART_STC15W) ? 3 : 2;
      h= new cl_pca_stc12(this, 0, pca_modules);
      h->init();
      add_hw(h);
    }
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
  if (stc_part == STC_PART_STC89)
    {
      /* STC89: standard 8052 clear — includes T2CON at 0xC8 */
      cl_uc52::clear_sfr();
      return;
    }

  /* STC12/STC15/STC15W: call cl_51core's clear, NOT cl_uc52's
     (which writes T2CON etc. — on STC12, 0xC8 is P5, not T2CON). */
  cl_51core::clear_sfr();

  bool has_p4p5= (stc_part == STC_PART_STC12 || stc_part == STC_PART_STC15);

  /* AUXR: 12T mode for timers */
  sfr->write(AUXR,  0x00);

  /* Port mode registers */
  sfr->write(STC12_P0M1, 0x00);
  sfr->write(STC12_P0M0, 0x00);
  sfr->write(STC12_P1M1, 0x00);
  sfr->write(STC12_P1M0, 0x00);
  sfr->write(STC12_P2M1, 0x00);
  sfr->write(STC12_P2M0, 0x00);
  sfr->write(STC12_P3M1, 0x00);
  sfr->write(STC12_P3M0, 0x00);
  if (has_p4p5)
    {
      sfr->write(STC12_P4M1, 0x00);
      sfr->write(STC12_P4M0, 0x00);
      sfr->write(STC12_P5M1, 0x00);
      sfr->write(STC12_P5M0, 0x00);
    }

  sfr->write(STC12_CLK_DIV, 0x00);
  sfr->write(STC12_P1ASF, 0x00);
  if (stc_part == STC_PART_STC12)
    sfr->write(STC12_P4SW, 0x00);

  /* ADC */
  sfr->write(STC12_ADC_CONTR, 0x00);
  sfr->write(STC12_ADC_RES,  0x00);
  sfr->write(STC12_ADC_RESL, 0x00);

  /* Extra ports */
  if (has_p4p5)
    {
      sfr->write(STC12_P4, 0xff);  /* ports reset high */
      sfr->write(STC12_P5, 0xff);
    }

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


/*
 * Differential execution trace.
 *
 * When enabled via trace_start(), do_inst() snapshots watched SFRs before
 * and after each instruction (including ISR entry/exit and all hw ticks).
 * This catches transient SFR states like TF0 that an ISR clears within
 * the same instruction context.
 */

void
cl_uc_stc12::trace_start(FILE *f, unsigned long fosc, unsigned long long until_ns)
{
  trace_file= f;
  trace_fosc= fosc;
  trace_until_ns= until_ns;
  trace_osc_clocks= 0;
  trace_last_pc= 0xFFFF;

  /* Snapshot initial SFR state */
  for (int i= 0; i < STC12_TRACE_NWATCH; i++)
    trace_sfr_shadow[i]= sfr->get(trace_sfr_addrs[i]);

  /* Snapshot full SFR range for unmodelled-register detection */
  for (int i= 0; i < 128; i++)
    trace_full_sfr_shadow[i]= sfr->get(0x80 + i);
  memset(trace_unmodelled_reported, 0, sizeof(trace_unmodelled_reported));
}

void
cl_uc_stc12::trace_check_sfr(void)
{
  if (!trace_file)
    return;

  unsigned long long t_ns= trace_osc_clocks * 1000000000ULL / trace_fosc;

  for (int i= 0; i < STC12_TRACE_NWATCH; i++)
    {
      t_mem val= sfr->get(trace_sfr_addrs[i]);
      if (val != trace_sfr_shadow[i])
	{
	  fprintf(trace_file, "%llu\tSFR\t%02X %02X\n",
		  (unsigned long long)t_ns,
		  (unsigned)trace_sfr_addrs[i], (unsigned)val);

	  /* PIN events: per-bit for port SFR changes */
	  {
	    static const struct { t_addr port; int id; t_addr m1; t_addr m0; }
	      port_map[] = {
		{0x80, 0, 0x93, 0x94}, /* P0 */
		{0x90, 1, 0x91, 0x92}, /* P1 */
		{0xA0, 2, 0x95, 0x96}, /* P2 */
		{0xB0, 3, 0xB1, 0xB2}, /* P3 */
		{0xC0, 4, 0xB3, 0xB4}, /* P4 */
	    };
	    for (unsigned p= 0; p < 5; p++)
	      {
		if (trace_sfr_addrs[i] == port_map[p].port)
		  {
		    t_mem old= trace_sfr_shadow[i];
		    t_mem m1= sfr->get(port_map[p].m1);
		    t_mem m0= sfr->get(port_map[p].m0);
		    for (int bit= 0; bit < 8; bit++)
		      {
			if ((val ^ old) & (1 << bit))
			  {
			    int mode= ((m1 >> bit) & 1) << 1 | ((m0 >> bit) & 1);
			    static const char *modes[] = {"Q","PP","IN","OD"};
			    fprintf(trace_file, "%llu\tPIN\t%d.%d %s %c\n",
				    (unsigned long long)t_ns,
				    port_map[p].id, bit, modes[mode],
				    (val & (1 << bit)) ? 'H' : 'L');
			  }
		      }
		    break;
		  }
	      }
	  }

	  /* TF events: detect rising edge of TF0 (bit 5) or TF1 (bit 7) */
	  if (trace_sfr_addrs[i] == 0x88)
	    {
	      t_mem old= trace_sfr_shadow[i];
	      if ((val & 0x20) && !(old & 0x20))
		fprintf(trace_file, "%llu\tTF\t0\n", (unsigned long long)t_ns);
	      if ((val & 0x80) && !(old & 0x80))
		fprintf(trace_file, "%llu\tTF\t1\n", (unsigned long long)t_ns);
	    }

	  /* ADC completion */
	  if (trace_sfr_addrs[i] == 0xBC)
	    {
	      t_mem old= trace_sfr_shadow[i];
	      if ((val & 0x10) && !(old & 0x10))
		{
		  /* Read the 10-bit result */
		  t_mem adc_res= sfr->get(STC12_ADC_RES);
		  t_mem adc_resl= sfr->get(STC12_ADC_RESL);
		  t_mem auxr1= sfr->get(AUXR1);
		  unsigned result;
		  if (auxr1 & 0x04)
		    result= ((unsigned)(adc_res & 0x03) << 8) | adc_resl;
		  else
		    result= ((unsigned)adc_res << 2) | (adc_resl & 0x03);
		  fprintf(trace_file, "%llu\tADC\t%d %u\n",
			  (unsigned long long)t_ns,
			  (int)(val & 0x07), result);
		}
	    }

	  trace_sfr_shadow[i]= val;
	}
    }

  /* Scan full SFR range for writes to unmodelled registers */
  for (int i= 0; i < 128; i++)
    {
      t_mem val= sfr->get(0x80 + i);
      if (val != trace_full_sfr_shadow[i])
	{
	  trace_full_sfr_shadow[i]= val;
	  bool defined= (stc_part == STC_PART_STC89)
	    ? stc89_sfr_defined[i] : stc12_sfr_defined[i];
	  if (!defined && !trace_unmodelled_reported[i])
	    {
	      unsigned long long t_ns= trace_osc_clocks * 1000000000ULL / trace_fosc;
	      fprintf(trace_file, "%llu\tUNMODELLED\t%02X %02X\n",
		      (unsigned long long)t_ns, (unsigned)(0x80 + i), (unsigned)val);
	      trace_unmodelled_reported[i]= true;
	    }
	}
    }
}

int
cl_uc_stc12::tick_hw(int cycles)
{
  int ret= cl_uc::tick_hw(cycles);

  /* Check SFRs after each hw tick — catches TF0 set by timer
     before the ISR has a chance to clear it. */
  if (trace_file)
    {
      /* On a 1T core (STC12/STC15), cycles = osc clocks (clock_per_cycle=1).
	 On a 12T core (STC89), cycles = machine cycles, each = 12 osc clocks.
	 trace_osc_clocks must always be in oscillator clocks. */
      trace_osc_clocks += (unsigned long long)cycles * clock_per_cycle();
      trace_check_sfr();
    }

  return ret;
}

int
cl_uc_stc12::do_inst(void)
{
  if (!trace_file)
    return cl_51core::do_inst();

  unsigned long long t_ns= trace_osc_clocks * 1000000000ULL / trace_fosc;
  if (t_ns > trace_until_ns)
    return resSTOP;

  /* Emit PC event */
  if (PC != trace_last_pc)
    {
      fprintf(trace_file, "%llu\tPC\t%04X\n",
	      (unsigned long long)t_ns, (unsigned)PC);
      trace_last_pc= PC;
    }

  /* Run the instruction (tick_hw will update trace_osc_clocks
     and check SFRs per-tick, catching transient TF0). */
  int result= cl_51core::do_inst();

  /* Check again after the full instruction + ISR handling.
     tick_hw catches TF0 being SET, but the ISR may clear it
     and restore TCON before we return. This second check
     catches the post-ISR state. */
  trace_check_sfr();

  return result;
}


/*
 * Debug target API (boundary D §7).
 *
 * Level 1 position: read bw_ms / <task>_state / <task>_until from IRAM.
 * Yield breakpoints: code breakpoints on case-label addresses.
 * Step: run N instructions and return final PC.
 */

void
cl_uc_stc12::debug_set_bw_ms(t_addr iram_addr)
{
  bw_ms_addr= iram_addr;
}

void
cl_uc_stc12::debug_add_task(const char *name, t_addr state_addr,
			    t_addr until_addr, t_addr func_addr)
{
  if (n_tasks >= STC12_MAX_TASKS)
    return;
  task_info[n_tasks].name= name;
  task_info[n_tasks].state_addr= state_addr;
  task_info[n_tasks].until_addr= until_addr;
  task_info[n_tasks].func_addr= func_addr;
  n_tasks++;
}

int
cl_uc_stc12::debug_add_yield_bp(int task_idx, unsigned int state,
				t_addr code_addr)
{
  if (n_yield_bps >= STC12_MAX_YIELD_BPS)
    return -1;
  yield_bps[n_yield_bps].active= true;
  yield_bps[n_yield_bps].task_idx= task_idx;
  yield_bps[n_yield_bps].state= state;
  yield_bps[n_yield_bps].code_addr= code_addr;
  /* Install as a code breakpoint in ucsim's breakpoint infrastructure */
  class cl_brk *b= fbrk->get_bp(code_addr, 0);
  if (!b)
    {
      b= new cl_fetch_brk(rom, make_new_brknr(), code_addr, brkFIX, 1);
      b->init();
      fbrk->add_bp(b);
    }
  return n_yield_bps++;
}

unsigned int
cl_uc_stc12::debug_read_bw_ms(void)
{
  if (!bw_ms_addr || !iram)
    return 0;
  /* 16-bit little-endian in IRAM */
  return iram->get(bw_ms_addr) | (iram->get(bw_ms_addr + 1) << 8);
}

unsigned int
cl_uc_stc12::debug_read_task_state(int task_idx)
{
  if (task_idx < 0 || task_idx >= n_tasks || !iram)
    return 0xFFFF;
  t_addr a= task_info[task_idx].state_addr;
  return iram->get(a) | (iram->get(a + 1) << 8);
}

unsigned int
cl_uc_stc12::debug_read_task_until(int task_idx)
{
  if (task_idx < 0 || task_idx >= n_tasks || !iram)
    return 0;
  t_addr a= task_info[task_idx].until_addr;
  return iram->get(a) | (iram->get(a + 1) << 8);
}

t_addr
cl_uc_stc12::debug_step_insn(int count)
{
  bool old_stop= stop_selfjump;
  stop_selfjump= false;

  for (int i= 0; i < count; i++)
    {
      int res= cl_51core::do_inst();
      if (res != resGO && res != resSELFJUMP)
	break;
    }

  stop_selfjump= old_stop;
  return PC;
}


/* End of s51.src/ucstc12.cc */
