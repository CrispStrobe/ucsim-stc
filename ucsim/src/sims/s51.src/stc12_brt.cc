/*
 * STC12 BRT (Baud Rate Timer) — 8-bit auto-reload timer for UART baud.
 *
 * When AUXR.BRTR=1 (bit 4), the BRT runs. When AUXR.S1BRS=1 (bit 0),
 * the serial port takes its baud clock from BRT overflows instead of
 * Timer 1. AUXR.BRTx12=1 (bit 2) selects FOSC; 0 selects FOSC/12.
 *
 * On overflow, the counter reloads from BRT (0x9C) and notifies the
 * serial port via hw_event EV_OVERFLOW with timer id 1 — the serial
 * model treats any Timer-1-id overflow as a baud tick, which is the
 * same interface the standard Timer 1 uses.
 *
 * Copyright (C) 2026 CrispStrobe
 * GPL-2.0-or-later
 */

#include "stc12_brtcl.h"
#include "regs51.h"
#include "uccl.h"

#define BRT_ADDR   0x9C
#define AUXR_BRTR  0x10   /* bit 4: BRT run */
#define AUXR_BRTx12 0x04  /* bit 2: 1T mode */
#define AUXR_S1BRS 0x01   /* bit 0: UART1 uses BRT */


cl_stc12_brt::cl_stc12_brt(class cl_uc *auc):
  cl_hw(auc, HW_TIMER, 3, "stc12_brt")
{
  cell_brt= 0;
  cell_auxr= 0;
  prescaler= 0;
  counter= 0;
}

int
cl_stc12_brt::init(void)
{
  class cl_address_space *sfr= uc->address_space(MEM_SFR_ID);
  if (sfr)
    {
      cell_brt= sfr->get_cell(BRT_ADDR);
      cell_auxr= register_cell(sfr, AUXR);
    }
  /* Register the serial port as a partner so inform_partners()
     delivers overflow events to it. */
  make_partner(HW_UART, 0);
  return 0;
}

int
cl_stc12_brt::tick(int cycles)
{
  if (!cell_auxr || !cell_brt)
    return resGO;

  t_mem auxr= cell_auxr->get();

  /* BRTR must be set for the BRT to run */
  if (!(auxr & AUXR_BRTR))
    return resGO;

  /* S1BRS must be set for the serial port to use BRT overflows.
     If S1BRS=0, the serial port uses Timer 1 and BRT does nothing
     useful — but it still counts if BRTR=1. We only bother counting
     when S1BRS=1, since the overflow notification is the whole point. */
  bool brt_1t= (auxr & AUXR_BRTx12) != 0;

  int effective= 0;
  if (brt_1t)
    {
      /* 1T mode: count at FOSC. tick() is called once per machine cycle;
         on a 1T CPU that is once per osc clock, so pass through. */
      effective= cycles;
    }
  else
    {
      /* 12T mode: count at FOSC/12. */
      prescaler += cycles;
      effective= prescaler / 12;
      prescaler %= 12;
    }

  if (effective <= 0)
    return resGO;

  t_mem reload= cell_brt->get();

  for (int i= 0; i < effective; i++)
    {
      counter++;
      if (counter == 0)
        {
          /* Overflow — reload and notify serial port.
             Use timer id 1 and EV_OVERFLOW, which is what the serial
             model's happen() method listens for. */
          counter= (unsigned char)reload;
          if (auxr & AUXR_S1BRS)
            inform_partners(EV_OVERFLOW, 0);
        }
    }

  return resGO;
}

void
cl_stc12_brt::print_info(class cl_console_base *con)
{
  t_mem auxr= cell_auxr ? cell_auxr->get() : 0;
  bool running= (auxr & AUXR_BRTR) != 0;
  bool one_t= (auxr & AUXR_BRTx12) != 0;
  bool selected= (auxr & AUXR_S1BRS) != 0;
  t_mem reload= cell_brt ? cell_brt->get() : 0;
  int divisor= 256 - (int)reload;

  con->dd_printf("STC12 BRT: %s, %s, %s for UART1",
                 running ? "running" : "stopped",
                 one_t ? "1T" : "12T",
                 selected ? "selected" : "not selected");
  con->dd_printf(", reload=0x%02X (divisor %d)\n",
                 (unsigned)reload, divisor);
}
