/*
 * stc15_uart_tx.c — STC15 UART TX via Timer 2 baud rate.
 *
 * Initializes UART1 at 115200 baud using Timer 2 (the STC15's baud source),
 * then transmits "Hi" (0x48 0x69). The trace should show P3.1 (TXD) toggling
 * with the correct bit timing.
 *
 * Compiled for STC15F2K60S2.
 *   sdcc -mmcs51 --model-small --no-xinit-opt stc15_uart_tx.c
 *
 * Timer 2 baud setup (matches 10-live-firmware STC15 path):
 *   T2_RELOAD = 65536 - (FOSC/(32*BAUD)) = 65536 - 3 = 0xFFFD
 *   AUXR = 0x15 → T2R=1, T2x12=1, S1ST2=1
 *   Baud = 11059200 / (32 * 3) = 115200 exactly
 *
 * Expected P3.1 (TXD) activity:
 *   Idle high, start bit low, 8 data bits LSB first, stop bit high.
 *   Bit time = 1/115200 ≈ 8.68 µs = 95.83 osc clocks at 11.0592 MHz
 */

#include <8051.h>

__sfr __at(0x8E) AUXR;
__sfr __at(0xD6) T2H;
__sfr __at(0xD7) T2L;

#define FOSC_HZ   11059200UL
#define BAUD      115200UL
#define BAUD_DIV  (FOSC_HZ / (32UL * BAUD))
#define T2_RELOAD (65536UL - BAUD_DIV)

static void uart_putc(unsigned char c)
{
    SBUF = c;
    while (!TI)
        ;
    TI = 0;
}

void main(void)
{
    /* UART1 mode 1, RX enabled */
    SCON = 0x50;

    /* Timer 2 baud rate: 16-bit reload */
    T2L = (unsigned char)(T2_RELOAD & 0xFF);
    T2H = (unsigned char)((T2_RELOAD >> 8) & 0xFF);

    /* T2R=1 (run), T2x12=1 (1T), S1ST2=1 (Timer 2 as UART1 source) */
    AUXR |= 0x15;

    TI = 0;
    RI = 0;

    /* Send "Hi" */
    uart_putc(0x48);   /* 'H' */
    uart_putc(0x69);   /* 'i' */

    /* Spin */
    for (;;) {}
}
