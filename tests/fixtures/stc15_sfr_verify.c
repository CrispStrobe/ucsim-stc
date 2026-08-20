/*
 * stc15_sfr_verify.c — STC15 SFR map + delta trap verification.
 *
 * Probes the three delta traps (STC15 vs STC12) and key SFR presence.
 * Run under stc12_trace with -t STC15 and verify UNMODELLED vs modelled
 * SFR writes by looking at trace output.
 *
 * Compiled for STC15F2K60S2 (1T core).
 *   sdcc -mmcs51 --model-small --no-xinit-opt stc15_sfr_verify.c
 *
 * Delta trap 1: ADRJ moved from AUXR1 (0xA2) bit 2 → CLK_DIV (0x97) bit 5
 *   - Write 0x97 = 0x20 (set CLK_DIV.5 = ADRJ on STC15)
 *   - Write 0xA2 = 0x04 (set AUXR1.2 = old ADRJ location — STC15 uses this
 *     as P_SW1 peripheral switch, NOT ADRJ)
 *
 * Delta trap 2: AUXR lower bits — BRT → Timer 2
 *   - Write AUXR = 0x15 (T2R=1, T2x12=1, S1ST2=1 on STC15)
 *   - Write T2H (0xD6) and T2L (0xD7) — must be modelled on STC15
 *   - Write BRT (0x9C) — deprecated on STC15, may be unmodelled
 *
 * Delta trap 3: WAKE_CLKO → INT_CLKO at 0x8F
 *   - Write 0x8F = 0x01 (T0CLKO on STC15's INT_CLKO)
 *
 * STC15-only SFRs that must be modelled:
 *   P5 (0xC8), P5M1 (0xC9), P5M0 (0xCA)
 *   T2H (0xD6), T2L (0xD7)
 *   INT_CLKO (0x8F)
 *   SPSTAT (0xCD), SPCTL (0xCE), SPDAT (0xCF)
 *   WKTCL (0xAA), WKTCH (0xAB)
 *
 * SFRs that must be ABSENT on STC15 (refused/unmodelled):
 *   P4SW (0xBB) — removed, job done by P_SW1/P_SW2
 *   T4T3M (0xD1), T4H (0xD2), T4L (0xD3), T3H (0xD4), T3L (0xD5)
 */

#include <8051.h>

/* STC15-specific SFRs */
__sfr __at(0x8E) AUXR;
__sfr __at(0x8F) INT_CLKO;    /* WAKE_CLKO on STC12, INT_CLKO on STC15 */
__sfr __at(0x97) CLK_DIV;     /* CLK_DIV/PCON2 — contains ADRJ on STC15 */
__sfr __at(0x9C) BRT;         /* deprecated on STC15 */
__sfr __at(0xA1) BUS_SPEED;
__sfr __at(0xA2) AUXR1;       /* P_SW1 on STC15 */
__sfr __at(0xAA) WKTCL;
__sfr __at(0xAB) WKTCH;
__sfr __at(0xBA) P_SW2;
__sfr __at(0xBB) P4SW;        /* absent on STC15 */
__sfr __at(0xC8) P5;
__sfr __at(0xC9) P5M1;
__sfr __at(0xCA) P5M0;
__sfr __at(0xCD) SPSTAT;
__sfr __at(0xCE) SPCTL;
__sfr __at(0xCF) SPDAT;
__sfr __at(0xD1) T4T3M;       /* absent on STC15F2K60S2 */
__sfr __at(0xD6) T2H;
__sfr __at(0xD7) T2L;

void main(void)
{
    /* --- Delta trap 1: ADRJ location --- */
    CLK_DIV = 0x20;            /* Set ADRJ (bit 5) on STC15 */
    AUXR1 = 0x04;              /* Old ADRJ location — now P_SW1 on STC15 */

    /* --- Delta trap 2: AUXR baud bits = Timer 2 --- */
    T2L = 0xFD;                /* Timer 2 reload low */
    T2H = 0xFF;                /* Timer 2 reload high */
    AUXR = 0x15;               /* T2R=1, T2x12=1, S1ST2=1 */

    /* --- Delta trap 3: INT_CLKO --- */
    INT_CLKO = 0x01;           /* T0CLKO on STC15 */

    /* --- STC15-present SFRs --- */
    P5 = 0xAA;                 /* Port 5 data */
    P5M0 = 0xFF;               /* Port 5 mode (push-pull) */
    BUS_SPEED = 0x01;
    WKTCL = 0x55;              /* Wake-up timer */
    WKTCH = 0x80;
    P_SW2 = 0x00;

    /* --- STC15-absent SFRs (should trigger UNMODELLED) --- */
    P4SW = 0x30;               /* absent on STC15 */
    T4T3M = 0x01;              /* Timer 3/4 — not on STC15F2K60S2 */

    /* --- Deprecated on STC15 --- */
    BRT = 0xFD;                /* deprecated, may be unmodelled */

    /* Spin */
    for (;;) {}
}
