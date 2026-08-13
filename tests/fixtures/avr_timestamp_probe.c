/*
 * avr_timestamp_probe.c — self-timestamping ATmega328P probe.
 *
 * Toggles PB5 (D13, LED) every 500 ms and prints the timestamp
 * over UART0 at 9600 baud.  Uses Timer1 in normal mode at FOSC/8
 * (2 MHz tick at 16 MHz) as the time base, maintaining a 32-bit
 * millisecond counter via overflow ISR.
 *
 * Build:
 *   avr-gcc -mmcu=atmega328p -Os -o tests/fixtures/avr_timestamp_probe.elf \
 *     tests/fixtures/avr_timestamp_probe.c
 *   avr-objcopy -O ihex avr_timestamp_probe.elf avr_timestamp_probe.ihx
 */

#include <avr/io.h>
#include <avr/interrupt.h>

#define F_CPU 16000000UL
#define BAUD 9600
#define UBRR_VAL ((F_CPU / 16 / BAUD) - 1)

/* Timer1 prescaler /8 → 2 MHz tick. Overflow every 32.768 ms. */
#define TIMER1_PRESCALER 8
#define TICKS_PER_MS     (F_CPU / TIMER1_PRESCALER / 1000)   /* 2000 */
#define TICKS_PER_OVF    65536UL
#define MS_PER_OVF       (TICKS_PER_OVF / TICKS_PER_MS)      /* 32 */

static volatile uint32_t ms_counter;

ISR(TIMER1_OVF_vect) {
    ms_counter += MS_PER_OVF;
}

static uint32_t now_ms(void) {
    uint32_t ms;
    uint16_t tcnt;
    uint8_t sreg = SREG;
    cli();
    ms = ms_counter;
    tcnt = TCNT1;
    /* If overflow flag is set and tcnt is low, OVF just fired before cli */
    if ((TIFR1 & (1 << TOV1)) && tcnt < 0x8000) {
        ms += MS_PER_OVF;
    }
    SREG = sreg;
    return ms + tcnt / TICKS_PER_MS;
}

static void uart_init(void) {
    UBRR0H = (uint8_t)(UBRR_VAL >> 8);
    UBRR0L = (uint8_t)UBRR_VAL;
    UCSR0B = (1 << TXEN0);
    UCSR0C = (1 << UCSZ01) | (1 << UCSZ00); /* 8N1 */
}

static void uart_putc(char c) {
    while (!(UCSR0A & (1 << UDRE0))) {}
    UDR0 = c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static void uart_print_u32(uint32_t v) {
    char buf[11];
    int i = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    while (i--) uart_putc(buf[i]);
}

int main(void) {
    /* PB5 = output (D13 LED) */
    DDRB |= (1 << DDB5);
    PORTB &= ~(1 << PORTB5);  /* start OFF */

    uart_init();

    /* Timer1: normal mode, prescaler /8 */
    TCCR1A = 0;
    TCCR1B = (1 << CS11);   /* /8 */
    TIMSK1 = (1 << TOIE1);  /* overflow interrupt */
    sei();

    uart_puts("START\r\n");

    uint32_t deadline = 500;
    while (deadline <= 3000) {
        while (now_ms() < deadline) {}

        /* Toggle PB5 */
        PINB = (1 << PINB5);  /* toggle via write to PIN register */

        uart_print_u32(now_ms());
        uart_puts("\r\n");

        deadline += 500;
    }

    uart_puts("DONE\r\n");
    cli();
    for (;;) {}
}
