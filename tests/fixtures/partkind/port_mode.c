/* port_mode.c — exercise all 4 port modes on P1.0
 * Part kinds exercised: source-vs-sink topology (push-pull, quasi-bidir,
 *   input-only, open-drain)
 * MCU peripheral: P1M1/P1M0 port mode register
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
    /* Mode 00: quasi-bidirectional (default) */
    P1M1 &= ~0x01; P1M0 &= ~0x01;
    P1_0 = 0; delay_ms(1);
    P1_0 = 1; delay_ms(1);

    /* Mode 01: push-pull */
    P1M1 &= ~0x01; P1M0 |= 0x01;
    P1_0 = 0; delay_ms(1);
    P1_0 = 1; delay_ms(1);

    /* Mode 10: input-only (high-Z) */
    P1M1 |= 0x01; P1M0 &= ~0x01;
    delay_ms(1);

    /* Mode 11: open-drain */
    P1M1 |= 0x01; P1M0 |= 0x01;
    P1_0 = 0; delay_ms(1);
    P1_0 = 1; delay_ms(1);

    while (1) ;
}
