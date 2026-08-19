/*
 * matrix8x8_bcm4.c — MATRIX8X8 BCM 4-level brightness golden trace fixture.
 *
 * Sets rows 0-3 to brightness levels 3, 2, 1, 0 (full row fills),
 * rows 4-7 left dark (level 0). Verifies the 3-phase BCM bit-plane
 * render produces the correct column port byte per row per phase.
 *
 * Compiled for STC89C52RC (standard 8051, 12T).
 *   sdcc -mmcs51 --model-small --no-xinit-opt matrix8x8_bcm4.c
 *
 * Frame buffer layout (2 planes, 8 rows each):
 *   plane0[0..7] = bw_scr[0..7]    (LSB of level)
 *   plane1[0..7] = bw_scr[8..15]   (MSB of level)
 *
 * Test pattern:
 *   Row 0: level 3 → plane0=0xFF, plane1=0xFF (binary 11)
 *   Row 1: level 2 → plane0=0x00, plane1=0xFF (binary 10)
 *   Row 2: level 1 → plane0=0xFF, plane1=0x00 (binary 01)
 *   Row 3: level 0 → plane0=0x00, plane1=0x00 (binary 00)
 *   Rows 4-7: level 0 (dark)
 *
 * BCM phase render (P0 = ~bw_lit, active-low columns):
 *   Phase 0 (p0|p1): row0=00 row1=00 row2=00 row3=FF r4-7=FF
 *   Phase 1 (p1):    row0=00 row1=00 row2=FF row3=FF r4-7=FF
 *   Phase 2 (p0&p1): row0=00 row1=FF row2=FF row3=FF r4-7=FF
 *
 * Duty per row: row0=3/3, row1=2/3, row2=1/3, row3=0/3
 */

#include <8051.h>

__sfr __at(0x8E) AUXR;

__sbit __at(0xB4) P3_4;   /* 595 SER (data) */
__sbit __at(0xB5) P3_5;   /* 595 RCLK (latch) */
__sbit __at(0xB6) P3_6;   /* 595 SCLK (shift clock) */

#define FOSC_HZ   11059200UL
#define T0_RELOAD (65536UL - (FOSC_HZ / 12UL / 1000UL))

#define MATRIX_PLANES 2
#define MATRIX_LEVELS 4

static unsigned char bw_scr[8 * MATRIX_PLANES];  /* 16-byte frame buffer */
static unsigned char scan;                        /* row cursor 0..7 */
static unsigned char phase;                       /* BCM phase 0..2 */
static unsigned char dim = MATRIX_LEVELS - 1;     /* global brightness cap */

static const __code unsigned char rowbit[8] =
    { 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 };

void isr_t0(void) __interrupt(1)
{
    unsigned char bw_lit, bw_rb, bw_i;

    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);

    P0 = 0xFF;                      /* blank columns during row change */
    bw_rb = rowbit[scan];

    /* Clock row byte into 595, MSB first */
    P3_5 = 0;                       /* RCLK low */
    for (bw_i = 0; bw_i < 8; bw_i++) {
        P3_4 = (bw_rb & 0x80) ? 1 : 0;   /* SER */
        bw_rb = (unsigned char)(bw_rb << 1);
        P3_6 = 1; P3_6 = 0;              /* SCLK pulse */
    }
    P3_5 = 1; P3_5 = 0;             /* RCLK pulse: latch to outputs */

    /* BCM phase render */
    if (dim > phase) {
        unsigned char p0 = bw_scr[scan];
        unsigned char p1 = bw_scr[scan + 8];
        if (phase == 0)      bw_lit = (unsigned char)(p0 | p1);
        else if (phase == 1) bw_lit = p1;
        else                 bw_lit = (unsigned char)(p0 & p1);
    } else {
        bw_lit = 0;
    }

    P0 = (unsigned char)~bw_lit;     /* active-low columns */

    /* Advance row; completed frame steps BCM phase */
    scan++;
    if (scan >= 8) {
        scan = 0;
        phase++;
        if (phase >= MATRIX_LEVELS - 1)
            phase = 0;
    }
}

static void set_row(unsigned char y, unsigned char level)
{
    unsigned char p;
    for (p = 0; p < MATRIX_PLANES; p++) {
        bw_scr[y + (unsigned char)(p << 3)] = (level & 1) ? 0xFF : 0x00;
        level = (unsigned char)(level >> 1);
    }
}

void main(void)
{
    /* 4-level test pattern: each row at a different brightness */
    set_row(0, 3);   /* level 3: plane0=FF, plane1=FF */
    set_row(1, 2);   /* level 2: plane0=00, plane1=FF */
    set_row(2, 1);   /* level 1: plane0=FF, plane1=00 */
    set_row(3, 0);   /* level 0: dark */
    /* rows 4-7 already zero (dark) */

    AUXR &= ~0x80;
    TMOD = (TMOD & 0xF0) | 0x01;

    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);
    ET0 = 1;
    EA  = 1;
    TR0 = 1;

    /* Spin — ISR drives the matrix */
    for (;;) {}
}
