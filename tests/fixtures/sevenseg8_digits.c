/*
 * sevenseg8_digits.c — SEVENSEG8 golden trace fixture.
 *
 * Drives an 8-digit 7-segment display (segments on P0, digit select
 * via P2.0/P2.1/P2.2 as 74HC138 address lines).  The frame buffer
 * is loaded with digits 1-8 (font-encoded) before the ISR starts.
 *
 * Compiled for STC89C52RC (standard 8051, 12T).
 *   sdcc -mmcs51 --model-small --no-xinit-opt sevenseg8_digits.c
 *
 * ISR scan order per tick:
 *   tick 0: digit 0  →  P2[2:0]=000  P0=font[1]=0x06
 *   tick 1: digit 1  →  P2[2:0]=001  P0=font[2]=0x5B
 *   tick 2: digit 2  →  P2[2:0]=010  P0=font[3]=0x4F
 *   tick 3: digit 3  →  P2[2:0]=011  P0=font[4]=0x66
 *   tick 4: digit 4  →  P2[2:0]=100  P0=font[5]=0x6D
 *   tick 5: digit 5  →  P2[2:0]=101  P0=font[6]=0x7D
 *   tick 6: digit 6  →  P2[2:0]=110  P0=font[7]=0x07
 *   tick 7: digit 7  →  P2[2:0]=111  P0=font[8]=0x7F
 *   (wraps at 8)
 */

#include <8051.h>

/* AUXR on STC12/15 — address 0x8E.  STC89 ignores this write but
 * the trace harness needs to see it not crash. */
__sfr __at(0x8E) AUXR;

/* P2 bit-addressable pins for digit select */
__sbit __at(0xA0) P2_0;
__sbit __at(0xA1) P2_1;
__sbit __at(0xA2) P2_2;

#define FOSC_HZ  11059200UL
#define T0_RELOAD (65536UL - (FOSC_HZ / 12UL / 1000UL))

/* 7-seg font: common cathode, standard encoding */
static const __code unsigned char font[16] = {
    0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07,
    0x7F, 0x6F, 0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71
};

static unsigned char fb[8];   /* frame buffer: one byte per digit */
static unsigned char cur;     /* current digit being scanned (0-7) */

void isr_t0(void) __interrupt(1)
{
    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);

    P0 = 0x00;          /* blank segments during digit switch */
    P2_0 = cur & 0x01 ? 1 : 0;
    P2_1 = cur & 0x02 ? 1 : 0;
    P2_2 = cur & 0x04 ? 1 : 0;
    P0 = fb[cur];       /* drive segment byte */

    cur = (cur + 1) & 0x07;
}

void main(void)
{
    /* Load frame buffer: digits 1 through 8 */
    fb[0] = font[1];    /* 0x06 */
    fb[1] = font[2];    /* 0x5B */
    fb[2] = font[3];    /* 0x4F */
    fb[3] = font[4];    /* 0x66 */
    fb[4] = font[5];    /* 0x6D */
    fb[5] = font[6];    /* 0x7D */
    fb[6] = font[7];    /* 0x07 */
    fb[7] = font[8];    /* 0x7F */

    AUXR &= ~0x80;      /* Timer 0 at FOSC/12 (no-op on STC89) */
    TMOD = (TMOD & 0xF0) | 0x01;  /* Timer 0, mode 1 */

    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);
    ET0 = 1;
    EA  = 1;
    TR0 = 1;

    /* Spin — ISR drives the display */
    for (;;) {}
}
