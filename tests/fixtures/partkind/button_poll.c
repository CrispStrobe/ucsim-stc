/* button_poll.c — poll P3.2 (button input), toggle P1.0 on low
 * Part kinds exercised: button, dip_switch, tilt_sensor, pir, ir_receiver,
 *   phototransistor (all are digital input)
 * MCU peripheral: GPIO input read, GPIO output
 *
 * Since both emulators start P3.2=1 (pull-up), and we can't inject
 * button presses, this program reads P3.2 in a loop and writes P1.0
 * based on the read value. The key observable is that both emulators
 * produce the same SFR trace for the port reads and writes.
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
    /* P1.0 push-pull output */
    P1M1 &= ~0x01;
    P1M0 |=  0x01;
    P1_0 = 1;

    /* Poll P3.2 three times with delay */
    for (i = 0; i < 3; i++) {
        if (P3_2 == 0) {
            P1_0 = !P1_0;  /* toggle on press */
        }
        delay_ms(1);
    }

    while (1) ;
}
