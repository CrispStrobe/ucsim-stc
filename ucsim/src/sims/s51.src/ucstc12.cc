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
}

int
cl_uc_stc12::tick_hw(int cycles)
{
  int ret= cl_uc::tick_hw(cycles);

  /* Check SFRs after each hw tick — catches TF0 set by timer
     before the ISR has a chance to clear it. */
  if (trace_file)
    {
      trace_osc_clocks += cycles;
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
