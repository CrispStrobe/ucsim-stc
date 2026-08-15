/* adc_multi.c — read ADC channel 2 twice, write results to P2
 * Part kinds exercised: potentiometer, ldr, ntc, tmp36, flex_sensor,
 *   force_sensor, soil_moisture, ambient_light, gas_sensor, photodiode
 *   (all are analog input via ADC)
 * MCU peripheral: ADC (P1ASF, ADC_CONTR, ADC_RES, ADC_RESL)
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

static unsigned char adc_read(unsigned char channel)
{
    ADC_CONTR = 0x80 | (channel & 0x07);  /* power on, select channel */
    delay_ms(1);
    ADC_CONTR |= 0x08;  /* start conversion */
    while (!(ADC_CONTR & 0x10)) ;  /* wait for ADC_FLAG */
    ADC_CONTR &= ~0x10;  /* clear flag */
    return ADC_RES;
}

void main(void)
{
    unsigned char r1, r2;

    /* P2 push-pull output for result display */
    P2M1 = 0x00;
    P2M0 = 0xFF;

    /* Enable P1.2 as analog input */
    P1ASF = 0x04;  /* bit 2 */

    r1 = adc_read(2);
    P2 = r1;
    delay_ms(1);

    r2 = adc_read(2);
    P2 = r2;

    while (1) ;
}
