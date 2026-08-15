/* dual_blink.c — 2-LED alternating blink (P1.0, P1.1)
 * Part kinds exercised: led (×2), resistor
 * MCU peripheral: GPIO output, Timer 0 (FOSC/12)
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
    P1M1 &= ~0x03;
    P1M0 |=  0x03;

    for (i = 0; i < 4; i++) {
        P1_0 = 0; P1_1 = 1;  /* LED1 on, LED2 off */
        delay_ms(1);
        P1_0 = 1; P1_1 = 0;  /* LED1 off, LED2 on */
        delay_ms(1);
    }
    P1 |= 0x03;
    while (1) ;
}
