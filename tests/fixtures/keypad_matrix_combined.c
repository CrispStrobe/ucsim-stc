/*
 * keypad_matrix_combined.c — KEYPAD4X4 + MATRIX8X8 combined golden trace.
 *
 * Mock keypad drives the matrix frame buffer: key press at ms>=10
 * lights row 5 (0xFF) via debounce, replacing the initial pattern.
 *
 * Compiled for STC89C52RC (standard 8051, 12T).
 *   sdcc -mmcs51 --model-small --no-xinit-opt keypad_matrix_combined.c
 *
 * Initial frame buffer (on/off, single plane, active-low columns):
 *   row 0: 0xAA → P0 = ~0xAA = 0x55
 *   row 1: 0x55 → P0 = ~0x55 = 0xAA
 *   rows 2-7: 0x00 → P0 = 0xFF
 *
 * After key 5 debounces (ms=15):
 *   row 5: 0xFF → P0 = ~0xFF = 0x00
 *
 * The ISR scans the matrix via 595 row select (P3.4/P3.5/P3.6)
 * and drives columns on P0 (active-low).
 *
 * Debounce timeline (5ms poll, two-agreeing-reads):
 *   ms=5:  read=-1, raw=-1 → key=-1
 *   ms=10: read=5,  raw=-1 → no debounce; raw←5
 *   ms=15: read=5,  raw=5  → key←5 (DEBOUNCED!)
 *   WHEN key 5: fb[5] = 0xFF
 *
 * Golden P0 per tick (one frame = 8 rows):
 *   Before key: 55 AA FF FF FF FF FF FF
 *   After key:  55 AA FF FF FF 00 FF FF
 */

#include <8051.h>

__sfr __at(0x8E) AUXR;

__sbit __at(0xB4) P3_4;   /* 595 SER */
__sbit __at(0xB5) P3_5;   /* 595 RCLK */
__sbit __at(0xB6) P3_6;   /* 595 SCLK */

#define FOSC_HZ   11059200UL
#define T0_RELOAD (65536UL - (FOSC_HZ / 12UL / 1000UL))

static unsigned char fb[8];           /* frame buffer */
static unsigned char scan_cur;        /* row cursor 0..7 */

static const __code unsigned char rowbit[8] =
    { 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 };

static volatile unsigned int bw_ms;

void isr_t0(void) __interrupt(1)
{
    unsigned char rb, i;

    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);
    bw_ms++;

    P0 = 0xFF;                  /* blank columns */
    rb = rowbit[scan_cur];

    /* 595 shift: MSB first */
    P3_5 = 0;
    for (i = 0; i < 8; i++) {
        P3_4 = (rb & 0x80) ? 1 : 0;
        rb = (unsigned char)(rb << 1);
        P3_6 = 1; P3_6 = 0;
    }
    P3_5 = 1; P3_5 = 0;

    P0 = (unsigned char)~fb[scan_cur];   /* active-low columns */

    scan_cur = (scan_cur + 1) & 0x07;
}

/* ---- atomic ms read ---- */
static unsigned int bw_now(void)
{
    unsigned int t;
    ET0 = 0;
    t = bw_ms;
    ET0 = 1;
    return t;
}

/* ---- mock keypad: returns 5 when ms >= 10 ---- */
static signed char mock_key_read(void)
{
    if (bw_now() >= 10) return 5;
    return -1;
}

/* ---- debounce (5ms, two-agreeing-reads) ---- */
static signed char kp_raw = -1;
static signed char kp_key = -1;
static unsigned int kp_t;

static void kp_poll(void)
{
    signed char r;
    if ((unsigned int)(bw_now() - kp_t) < 5)
        return;
    kp_t = bw_now();
    r = mock_key_read();
    if (r == kp_raw)
        kp_key = r;
    kp_raw = r;
}

/* ---- WHEN key 5 pressed ---- */
static unsigned char key5_prev;

static void task_key5(void)
{
    unsigned char now = (kp_key == 5) ? 1 : 0;
    unsigned char fired = (now && !key5_prev) ? 1 : 0;
    key5_prev = now;
    if (!fired) return;

    fb[5] = 0xFF;   /* light all columns on row 5 */
}

void main(void)
{
    /* initial pattern: checkerboard on rows 0-1 */
    fb[0] = 0xAA;
    fb[1] = 0x55;
    /* rows 2-7 already 0x00 (dark) */

    AUXR &= ~0x80;
    TMOD = (TMOD & 0xF0) | 0x01;

    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);
    ET0 = 1;
    EA  = 1;
    TR0 = 1;

    for (;;) {
        kp_poll();
        task_key5();
    }
}
