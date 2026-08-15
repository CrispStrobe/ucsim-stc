/* sos_morse.c — SOS pattern on P1.0 (dit-dit-dit dah-dah-dah dit-dit-dit)
 * Part kinds exercised: led, resistor, buzzer (same GPIO drive)
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

static void dit(void) { P1_0 = 0; delay_ms(1); P1_0 = 1; delay_ms(1); }
static void dah(void) { P1_0 = 0; delay_ms(3); P1_0 = 1; delay_ms(1); }

void main(void)
{
    P1M1 &= ~0x01;
    P1M0 |=  0x01;
    P1_0 = 1;

    dit(); dit(); dit();   /* S */
    delay_ms(2);           /* letter gap */
    dah(); dah(); dah();   /* O */
    delay_ms(2);
    dit(); dit(); dit();   /* S */

    while (1) ;
}
