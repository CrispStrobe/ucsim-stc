/* multi_led.c — 4-LED walking pattern (P1.0-P1.3)
 * Part kinds exercised: led (×4), resistor, bargraph
 * MCU peripheral: GPIO output (port mask write), Timer 0 (FOSC/12)
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
    unsigned char i;
    P1M1 &= ~0x0F;
    P1M0 |=  0x0F;
    P1 |= 0x0F;

    /* Walk pattern: one LED on at a time (active low) */
    for (i = 0; i < 4; i++) {
        P1 = (P1 | 0x0F) & ~(1 << i);
        delay_ms(1);
    }
    /* Reverse */
    for (i = 3; i > 0; i--) {
        P1 = (P1 | 0x0F) & ~(1 << (i - 1));
        delay_ms(1);
    }
    P1 |= 0x0F;
    while (1) ;
}
