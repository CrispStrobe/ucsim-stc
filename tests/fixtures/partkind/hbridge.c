/* hbridge.c — H-bridge motor control (L293D on P1.0/P1.1 direction, P1.2 enable)
 * Part kinds exercised: h_bridge, dc_motor, dc_motor_encoder, gearmotor
 * MCU peripheral: GPIO output (direction + enable), Timer 0
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
    /* P1.0=IN1, P1.1=IN2, P1.2=EN — all push-pull */
    P1M1 &= ~0x07;
    P1M0 |=  0x07;

    /* Stop */
    P1_0 = 0; P1_1 = 0; P1_2 = 0;
    delay_ms(1);

    /* Forward */
    P1_0 = 1; P1_1 = 0; P1_2 = 1;
    delay_ms(2);

    /* Stop */
    P1_0 = 0; P1_1 = 0; P1_2 = 0;
    delay_ms(1);

    /* Reverse */
    P1_0 = 0; P1_1 = 1; P1_2 = 1;
    delay_ms(2);

    /* Brake */
    P1_0 = 1; P1_1 = 1; P1_2 = 1;
    delay_ms(1);

    /* Off */
    P1_0 = 0; P1_1 = 0; P1_2 = 0;

    while (1) ;
}
