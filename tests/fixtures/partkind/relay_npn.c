/* relay_npn.c — NPN transistor driving a relay/motor/solenoid on P1.0
 * Part kinds exercised: relay, dc_motor (simple), solenoid, vibration_motor,
 *   light_bulb, optocoupler, darlington_driver, tip120
 *   (all are GPIO output driving an NPN/MOSFET)
 * MCU peripheral: GPIO output, Timer 0
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
    /* P1.0 push-pull output (NPN base drive) */
    P1M1 &= ~0x01;
    P1M0 |=  0x01;
    /* P1.1 push-pull output (status LED) */
    P1M1 &= ~0x02;
    P1M0 |=  0x02;

    P1_0 = 0; P1_1 = 1;  /* relay OFF, LED OFF */
    delay_ms(1);

    P1_0 = 1; P1_1 = 0;  /* relay ON, LED ON */
    delay_ms(2);

    P1_0 = 0; P1_1 = 1;  /* relay OFF, LED OFF */
    delay_ms(1);

    while (1) ;
}
