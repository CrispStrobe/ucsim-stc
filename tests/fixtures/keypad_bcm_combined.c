/*
 * keypad_bcm_combined.c — KEYPAD4X4 + MATRIX8X8 BCM brightness golden trace.
 *
 * Keypress-driven BCM brightness change: mock key 5 at ms>=10 upgrades
 * row 2 from level 1 to level 3, changing its duty from 1/3 to 3/3.
 *
 * Compiled for STC89C52RC (standard 8051, 12T).
 *   sdcc -mmcs51 --model-small --no-xinit-opt keypad_bcm_combined.c
 *
 * Initial BCM pattern (rows 0-3 at levels 3,2,1,0):
 *   plane0: [FF, 00, FF, 00, 00, 00, 00, 00]
 *   plane1: [FF, FF, 00, 00, 00, 00, 00, 00]
 *
 * After key 5 debounces (ms=15), row 2 → level 3:
 *   plane0: [FF, 00, FF, 00, 00, 00, 00, 00]  (unchanged)
 *   plane1: [FF, FF, FF, 00, 00, 00, 00, 00]  (row 2 bit set)
 *
 * Pre-key P0 per phase (active-low: P0 = ~bw_lit):
 *   Phase 0 (p0|p1): 00 00 00 FF FF FF FF FF
 *   Phase 1 (p1):    00 00 FF FF FF FF FF FF  ← row 2 dark
 *   Phase 2 (p0&p1): 00 FF FF FF FF FF FF FF  ← row 2 dark
 *
 * Post-key P0 per phase:
 *   Phase 0 (p0|p1): 00 00 00 FF FF FF FF FF  (unchanged)
 *   Phase 1 (p1):    00 00 00 FF FF FF FF FF  ← row 2 now lit!
 *   Phase 2 (p0&p1): 00 FF 00 FF FF FF FF FF  ← row 2 now lit!
 */

#include <8051.h>

__sfr __at(0x8E) AUXR;

__sbit __at(0xB4) P3_4;
__sbit __at(0xB5) P3_5;
__sbit __at(0xB6) P3_6;

#define FOSC_HZ   11059200UL
#define T0_RELOAD (65536UL - (FOSC_HZ / 12UL / 1000UL))

#define MATRIX_PLANES 2
#define MATRIX_LEVELS 4

static unsigned char bw_scr[8 * MATRIX_PLANES];
static unsigned char scan;
static unsigned char phase;
static unsigned char dim = MATRIX_LEVELS - 1;

static const __code unsigned char rowbit[8] =
    { 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 };

static volatile unsigned int bw_ms;

void isr_t0(void) __interrupt(1)
{
    unsigned char bw_lit, bw_rb, bw_i;

    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);
    bw_ms++;

    P0 = 0xFF;
    bw_rb = rowbit[scan];

    P3_5 = 0;
    for (bw_i = 0; bw_i < 8; bw_i++) {
        P3_4 = (bw_rb & 0x80) ? 1 : 0;
        bw_rb = (unsigned char)(bw_rb << 1);
        P3_6 = 1; P3_6 = 0;
    }
    P3_5 = 1; P3_5 = 0;

    if (dim > phase) {
        unsigned char p0 = bw_scr[scan];
        unsigned char p1 = bw_scr[scan + 8];
        if (phase == 0)      bw_lit = (unsigned char)(p0 | p1);
        else if (phase == 1) bw_lit = p1;
        else                 bw_lit = (unsigned char)(p0 & p1);
    } else {
        bw_lit = 0;
    }

    P0 = (unsigned char)~bw_lit;

    scan++;
    if (scan >= 8) {
        scan = 0;
        phase++;
        if (phase >= MATRIX_LEVELS - 1)
            phase = 0;
    }
}

static unsigned int bw_now(void)
{
    unsigned int t;
    ET0 = 0;
    t = bw_ms;
    ET0 = 1;
    return t;
}

/* ---- mock keypad ---- */
static signed char mock_key_read(void)
{
    if (bw_now() >= 10) return 5;
    return -1;
}

/* ---- debounce ---- */
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

/* ---- WHEN key 5 pressed: upgrade row 2 to level 3 ---- */
static unsigned char key5_prev;

static void task_key5(void)
{
    unsigned char now = (kp_key == 5) ? 1 : 0;
    unsigned char fired = (now && !key5_prev) ? 1 : 0;
    key5_prev = now;
    if (!fired) return;

    /* row 2: level 1 (plane0=FF, plane1=00) → level 3 (plane0=FF, plane1=FF) */
    bw_scr[2 + 8] = 0xFF;   /* set plane1 for row 2 */
}

static void set_row_level(unsigned char y, unsigned char level)
{
    unsigned char p;
    for (p = 0; p < MATRIX_PLANES; p++) {
        bw_scr[y + (unsigned char)(p << 3)] = (level & 1) ? 0xFF : 0x00;
        level = (unsigned char)(level >> 1);
    }
}

void main(void)
{
    set_row_level(0, 3);
    set_row_level(1, 2);
    set_row_level(2, 1);
    set_row_level(3, 0);

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
