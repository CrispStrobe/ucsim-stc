/* traffic_light.c — 3-LED timed sequence (red/yellow/green on P1.0-P1.2)
 * Part kinds exercised: led (×3), resistor
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
    /* Push-pull output on P1.0, P1.1, P1.2 */
    P1M1 &= ~0x07;
    P1M0 |=  0x07;
    P1 |= 0x07;  /* all off (active low) */

    /* Red on */
    P1 &= ~0x01; /* P1.0 = red ON */
    P1 |=  0x06; /* P1.1,P1.2 OFF */
    delay_ms(3);

    /* Green on */
    P1 |=  0x01; /* red OFF */
    P1 &= ~0x04; /* P1.2 = green ON */
    delay_ms(3);

    /* Yellow on */
    P1 |=  0x04; /* green OFF */
    P1 &= ~0x02; /* P1.1 = yellow ON */
    delay_ms(1);

    /* All off */
    P1 |= 0x07;

    while (1) ;
}
