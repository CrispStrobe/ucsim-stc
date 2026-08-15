/* shift_out.c — 74HC595 shift register output (data P1.0, clock P1.1, latch P1.2)
 * Part kinds exercised: shift_register (74hc595), 74hc95, bargraph, led_matrix
 * MCU peripheral: GPIO output (bit-bang SPI), Timer 0
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

#define DATA  P1_0
#define CLOCK P1_1
#define LATCH P1_2

static void shift_byte(unsigned char val)
{
    unsigned char i;
    for (i = 0; i < 8; i++) {
        DATA = (val & 0x80) ? 1 : 0;
        val <<= 1;
        CLOCK = 1;
        CLOCK = 0;
    }
    LATCH = 1;
    LATCH = 0;
}

void main(void)
{
    P1M1 &= ~0x07;
    P1M0 |=  0x07;
    DATA = 0; CLOCK = 0; LATCH = 0;

    shift_byte(0xA5);
    delay_ms(1);
    shift_byte(0x3C);
    delay_ms(1);
    shift_byte(0xFF);
    delay_ms(1);
    shift_byte(0x00);

    while (1) ;
}
