/* p5_mode.c — exercise P5 port modes on STC15
 * Part kinds exercised: P5 port latch/read, P5M1/P5M0 mode config
 * MCU peripheral: P5 (0xC8), P5M1 (0xC9), P5M0 (0xCA)
 *
 * P5 is STC15 only (refused on STC12). On PDIP-40 only P5.4 and P5.5
 * are bonded, but all 8 bits exist in the SFR.
 */
#include <stc12.h>

#define FOSC_HZ 11059200UL
#define T0_RELOAD (65536UL - (FOSC_HZ / 12UL / 1000UL))

static void delay_ms(unsigned int ms)
{
    while (ms--) {
        TL0 = (unsigned char)(T0_RELOAD & 0xFF);
        TH0 = (unsigned char)(T0_RELOAD >> 8);
        TF0 = 0;
        TR0 = 1;
        while (!TF0) ;
        TR0 = 0;
        TF0 = 0;
    }
}

void main(void)
{
    /* Mode 00: quasi-bidirectional (default) — toggle P5.5 (buzzer pin) */
    P5M1 &= ~0x20; P5M0 &= ~0x20;
    P5 &= ~0x20; delay_ms(1);
    P5 |=  0x20; delay_ms(1);

    /* Mode 01: push-pull */
    P5M1 &= ~0x20; P5M0 |= 0x20;
    P5 &= ~0x20; delay_ms(1);
    P5 |=  0x20; delay_ms(1);

    /* Mode 10: input-only (high-Z) */
    P5M1 |= 0x20; P5M0 &= ~0x20;
    delay_ms(1);

    /* Mode 11: open-drain */
    P5M1 |= 0x20; P5M0 |= 0x20;
    P5 &= ~0x20; delay_ms(1);
    P5 |=  0x20; delay_ms(1);

    while (1) ;
}
