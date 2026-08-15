/* port_full.c — full port P1 write (8 pins, all push-pull)
 * Part kinds exercised: led (×8), resistor, led_matrix, led_cube
 * MCU peripheral: full-port GPIO, port mode config, Timer 0
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
    /* All P1 push-pull */
    P1M1 = 0x00;
    P1M0 = 0xFF;

    /* Binary count on P1 */
    P1 = 0x00; delay_ms(1);
    P1 = 0x55; delay_ms(1);
    P1 = 0xAA; delay_ms(1);
    P1 = 0xFF; delay_ms(1);
    P1 = 0x0F; delay_ms(1);
    P1 = 0xF0; delay_ms(1);
    P1 = 0x00;

    while (1) ;
}
