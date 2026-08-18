/*
 * ledbank8_pattern.c — LEDBANK8 golden trace fixture.
 *
 * Drives 8 LEDs on P1 (active-low) via an ISR-owned shadow byte.
 * The shadow is set to 0xA5 before the ISR starts.
 *
 * Compiled for STC89C52RC (standard 8051, 12T).
 *   sdcc -mmcs51 --model-small --no-xinit-opt ledbank8_pattern.c
 *
 * ISR writes P1 = ~shadow every tick (active-low inversion).
 *   shadow = 0xA5  →  P1 = ~0xA5 = 0x5A every tick
 *
 * The test also verifies shared-P2 interaction: P2 is not driven
 * by this fixture, so it should remain at its reset default (0xFF
 * quasi-bidir high).  A second fixture variant adds SEVENSEG8 on P0
 * with digit select on P2, confirming the ISR ordering interaction.
 */

#include <8051.h>

/* AUXR on STC12/15 — address 0x8E */
__sfr __at(0x8E) AUXR;

#define FOSC_HZ  11059200UL
#define T0_RELOAD (65536UL - (FOSC_HZ / 12UL / 1000UL))

static unsigned char shadow;  /* LED shadow — ISR sole port writer */

void isr_t0(void) __interrupt(1)
{
    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);

    P1 = (unsigned char)~shadow;  /* active-low: invert shadow */
}

void main(void)
{
    shadow = 0xA5;       /* pattern: 10100101 */

    AUXR &= ~0x80;      /* Timer 0 at FOSC/12 (no-op on STC89) */
    TMOD = (TMOD & 0xF0) | 0x01;  /* Timer 0, mode 1 */

    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);
    ET0 = 1;
    EA  = 1;
    TR0 = 1;

    /* Spin — ISR drives LEDs */
    for (;;) {}
}
