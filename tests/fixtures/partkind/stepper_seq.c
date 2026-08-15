/* stepper_seq.c — 4-pin stepper motor half-step sequence on P1.0-P1.3
 * Part kinds exercised: stepper
 * MCU peripheral: GPIO output (4-pin sequence), Timer 0
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

/* Half-step sequence for unipolar stepper */
static const unsigned char __code steps[] = {
    0x01, 0x03, 0x02, 0x06, 0x04, 0x0C, 0x08, 0x09
};

void main(void)
{
    unsigned char i, j;
    P1M1 &= ~0x0F;
    P1M0 |=  0x0F;

    /* Two full revolutions worth of steps (2×8) */
    for (j = 0; j < 2; j++) {
        for (i = 0; i < 8; i++) {
            P1 = (P1 & 0xF0) | steps[i];
            delay_ms(1);
        }
    }

    P1 &= 0xF0;
    while (1) ;
}
