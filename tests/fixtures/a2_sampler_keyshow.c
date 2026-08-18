/*
 * a2_sampler_keyshow.c — A2 multi-device golden trace fixture.
 *
 * Combines three A2 PARTs in one program:
 *   SEVENSEG8  — segments on P0, digit select P2.0/P2.1/P2.2
 *   LEDBANK8   — 8 LEDs on P3, active-low
 *   KEYPAD4X4  — mock scanner (no physical pins), debounce state machine
 *
 * The keypad scanner is replaced by a mock that returns a predetermined
 * key at a known millisecond offset, so both emulators execute identical
 * code and produce identical traces without pin injection.
 *
 * Compiled for STC89C52RC (standard 8051, 12T).
 *   sdcc -mmcs51 --model-small --no-xinit-opt a2_sampler_keyshow.c
 *
 * Mock key timeline:
 *   bw_ms <  10: returns -1 (no key)
 *   bw_ms >= 10: returns  5 (key 5 pressed)
 *
 * Debounce (5ms poll, two-agreeing-reads):
 *   ms=5:  read=-1, raw=-1==read → key=-1 (agrees with init)
 *   ms=10: read=5,  raw=-1≠5    → key unchanged; raw←5
 *   ms=15: read=5,  raw=5==5    → key←5  (DEBOUNCED!)
 *
 * WHEN key 5 pressed fires at ms=15:
 *   - display digit 0 = font[5] = 0x6D
 *   - leds shadow = 0x20 (key_active flag stops chase)
 *
 * LEDBANK8 chase (before key fires):
 *   ms ~1: shadow=0x01 → P3=0xFE (first ISR write)
 *   ms  5: shadow=0x02 → P3=0xFD
 *   ms 10: shadow=0x04 → P3=0xFB
 *   ms 15: key fires   → shadow=0x20, P3=0xDF (chase stops)
 *
 * SEVENSEG8 per-tick:
 *   Before ms 15: digit 0 = font[0] = 0x3F, digits 1-7 = 0x00
 *   After  ms 15: digit 0 = font[5] = 0x6D
 */

#include <8051.h>

__sfr __at(0x8E) AUXR;

__sbit __at(0xA0) P2_0;
__sbit __at(0xA1) P2_1;
__sbit __at(0xA2) P2_2;

#define FOSC_HZ   11059200UL
#define T0_RELOAD (65536UL - (FOSC_HZ / 12UL / 1000UL))

/* ---- 7-seg font ---- */
static const __code unsigned char font[16] = {
    0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07,
    0x7F, 0x6F, 0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71
};

/* ---- SEVENSEG8 state ---- */
static unsigned char fb[8];
static unsigned char disp_cur;

/* ---- LEDBANK8 state ---- */
static unsigned char led_shadow;

/* ---- millisecond counter ---- */
static volatile unsigned int bw_ms;

/* ---- ISR: 1ms tick ---- */
void isr_t0(void) __interrupt(1)
{
    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);
    bw_ms++;

    /* SEVENSEG8: advance one digit */
    P0 = 0x00;
    P2_0 = disp_cur & 0x01 ? 1 : 0;
    P2_1 = disp_cur & 0x02 ? 1 : 0;
    P2_2 = disp_cur & 0x04 ? 1 : 0;
    P0 = fb[disp_cur];
    disp_cur = (disp_cur + 1) & 0x07;

    /* LEDBANK8: active-low */
    P3 = (unsigned char)~led_shadow;
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

/* ---- mock keypad scanner ---- */
static signed char mock_key_read(void)
{
    if (bw_now() >= 10) return 5;
    return -1;
}

/* ---- keypad debounce (5ms, two-agreeing-reads) ---- */
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

/* ---- WHEN key 5 pressed (edge-triggered on debounced key) ---- */
static unsigned char key5_prev;
static unsigned char key_active;

static void task_key5(void)
{
    unsigned char now = (kp_key == 5) ? 1 : 0;
    unsigned char fired = (now && !key5_prev) ? 1 : 0;
    key5_prev = now;
    if (!fired) return;

    /* body: update display and LEDs */
    fb[0] = font[5];      /* digit 0 shows "5" → 0x6D */
    led_shadow = 0x20;    /* LED 5 on → P3 = ~0x20 = 0xDF */
    key_active = 1;       /* stop the chase */
}

/* ---- LEDBANK8 chase (rotate left every 5ms, stops on key) ---- */
static unsigned char chase_step;
static unsigned int chase_t;

static void chase_poll(void)
{
    if (key_active) return;
    if ((unsigned int)(bw_now() - chase_t) < 5)
        return;
    chase_t = bw_now();
    chase_step++;
    led_shadow = (unsigned char)(1 << (chase_step & 0x07));
}

void main(void)
{
    /* initial state */
    fb[0] = font[0];      /* digit 0 shows "0" → 0x3F */
    led_shadow = 0x01;    /* chase starts at LED 0 */

    AUXR &= ~0x80;
    TMOD = (TMOD & 0xF0) | 0x01;

    TL0 = (unsigned char)(T0_RELOAD & 0xFF);
    TH0 = (unsigned char)(T0_RELOAD >> 8);
    ET0 = 1;
    EA  = 1;
    TR0 = 1;

    for (;;) {
        kp_poll();        /* debounce first */
        task_key5();      /* then check edge */
        chase_poll();     /* chase last (stopped by key_active) */
    }
}
