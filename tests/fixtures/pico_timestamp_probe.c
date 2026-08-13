/*
 * pico_timestamp_probe.c — self-timestamping RP2040 probe firmware.
 *
 * Flash-linked at 0x10000000 (labwired-core's load path expects real
 * Cortex-M vectors at 0x10000000 via the BOOTROM at address 0).
 * Exercises the generateC idioms: latched 64-bit TIMER read, PL011 UART0.
 *
 * At each 500 ms deadline, prints its own bw_now() value.  Two independent
 * emulators (rp2040js + labwired-core) printing the same sequence proves
 * timer/UART/scheduler fidelity without external timing measurement.
 *
 * Build:
 *   arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -nostdlib -Os \
 *     -T tests/fixtures/pico_flash.ld -o tests/fixtures/pico_timestamp_probe.elf \
 *     tests/fixtures/pico_timestamp_probe.c
 *
 * The linker script places .vector_table at 0x10000000 and .text after.
 */

#include <stdint.h>

/* ── Peripheral bases ── */
#define RESETS_BASE       0x4000C000u
#define CLOCKS_BASE       0x40008000u
#define IO_BANK0_BASE     0x40014000u
#define UART0_BASE        0x40034000u
#define TIMER_BASE        0x40054000u

/* ── RESETS ── */
#define RESETS_RESET       (*(volatile uint32_t *)(RESETS_BASE + 0x00))
#define RESETS_RESET_DONE  (*(volatile uint32_t *)(RESETS_BASE + 0x08))
#define RESETS_IO_BANK0    (1u << 5)
#define RESETS_PADS_BANK0  (1u << 8)
#define RESETS_UART0       (1u << 22)
#define RESETS_TIMER       (1u << 21)

/* ── CLOCKS ── */
#define CLK_PERI_CTRL      (*(volatile uint32_t *)(CLOCKS_BASE + 0x48))
#define CLK_PERI_ENABLE    (1u << 11)

/* ── IO_BANK0: GP0 → UART0 TX ── */
#define GPIO0_CTRL         (*(volatile uint32_t *)(IO_BANK0_BASE + 0x04))
#define GPIO_FUNC_UART     2u

/* ── UART0 (PL011) ── */
#define UART0_DR           (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART0_FR           (*(volatile uint32_t *)(UART0_BASE + 0x18))
#define UART0_IBRD         (*(volatile uint32_t *)(UART0_BASE + 0x24))
#define UART0_FBRD         (*(volatile uint32_t *)(UART0_BASE + 0x28))
#define UART0_LCR_H        (*(volatile uint32_t *)(UART0_BASE + 0x2C))
#define UART0_CR           (*(volatile uint32_t *)(UART0_BASE + 0x30))
#define FR_TXFF            (1u << 5)

/* IBRD/FBRD for 115200 at ~6.5 MHz ROSC (clk_peri from clk_sys).
 * BRD = 6500000 / (16 * 115200) = 3.5264 → IBRD=3, FBRD=34. */
#define UART_IBRD_VAL      3u
#define UART_FBRD_VAL      34u
#define LCR_H_8N1_FIFO    ((3u << 5) | (1u << 4))  /* WLEN=8, FEN=1 */
#define CR_UARTEN_TXE     ((1u << 0) | (1u << 8))

/* ── TIMER (64-bit µs counter) ──
 * Latched read: read TIMELR first (latches TIMEHR), then TIMEHR.
 * This is the bw_now() idiom from generateC. */
#define TIMELR  (*(volatile uint32_t *)(TIMER_BASE + 0x0C))
#define TIMEHR  (*(volatile uint32_t *)(TIMER_BASE + 0x10))

static void uart0_putc(char c) {
    while (UART0_FR & FR_TXFF) {}
    UART0_DR = (uint32_t)c;
}

static void uart0_puts(const char *s) {
    while (*s) uart0_putc(*s++);
}

static void uart0_print_u32(uint32_t v) {
    /* Division-free decimal print for Cortex-M0+ (-nostdlib).
     * Subtract powers of ten to extract digits. */
    static const uint32_t pow10[] = {
        1000000000u, 100000000u, 10000000u, 1000000u, 100000u,
        10000u, 1000u, 100u, 10u, 1u
    };
    if (v == 0) { uart0_putc('0'); return; }
    int started = 0;
    for (int i = 0; i < 10; i++) {
        char d = '0';
        while (v >= pow10[i]) { v -= pow10[i]; d++; }
        if (d != '0' || started) { uart0_putc(d); started = 1; }
    }
}

/* bw_now(): latched 64-bit µs read → ms.
 * Division-free: subtract 1000 in a loop (we only need values < ~10000 ms). */
static uint32_t bw_now_ms(void) {
    uint32_t lo = TIMELR;   /* latches TIMEHR */
    (void)TIMEHR;           /* consume latched high word */
    /* For our probe, lo alone suffices: 32 bits of µs = ~4295 seconds. */
    uint32_t ms = 0;
    while (lo >= 1000u) { lo -= 1000u; ms++; }
    return ms;
}

/* ── Init ── */
static void init(void) {
    /* Deassert resets for UART0, IO_BANK0, PADS_BANK0, TIMER. */
    uint32_t bits = RESETS_UART0 | RESETS_IO_BANK0 | RESETS_PADS_BANK0 | RESETS_TIMER;
    RESETS_RESET &= ~bits;
    while ((RESETS_RESET_DONE & bits) != bits) {}

    /* Enable clk_peri (AUXSRC already = clk_sys). */
    CLK_PERI_CTRL |= CLK_PERI_ENABLE;

    /* Mux GP0 → UART0 TX. */
    GPIO0_CTRL = GPIO_FUNC_UART;

    /* UART0: 115200 8N1, FIFO enabled. */
    UART0_IBRD = UART_IBRD_VAL;
    UART0_FBRD = UART_FBRD_VAL;
    UART0_LCR_H = LCR_H_8N1_FIFO;
    UART0_CR = CR_UARTEN_TXE;
}

/* ── Main: print bw_now_ms() at each 500 ms deadline ── */
void main(void) {
    init();

    uint32_t deadline_ms = 500;
    const uint32_t horizon_ms = 4000;

    while (deadline_ms <= horizon_ms) {
        /* Busy-wait until the timer reaches the deadline. */
        while (bw_now_ms() < deadline_ms) {}

        /* Print the current time (self-timestamp). */
        uart0_print_u32(bw_now_ms());
        uart0_putc('\n');

        deadline_ms += 500;
    }

    /* Done marker. */
    uart0_puts("DONE\n");

    /* Halt: infinite WFI loop. */
    while (1) { __asm volatile("wfi"); }
}

/* ── Cortex-M0+ startup: vector table + reset thunk ── */
extern unsigned long _estack;

__attribute__((naked, noreturn))
void Reset_Handler(void) {
    __asm volatile(
        "ldr r0, =_estack\n"
        "mov sp, r0\n"
        "bl main\n"
        "b .\n"
    );
}

/* Default handler for all exceptions/interrupts. */
__attribute__((weak))
void Default_Handler(void) { while (1) {} }

/* Vector table — placed at 0x10000000 by the linker script.
 * Word 0 = initial SP, word 1 = reset handler. */
__attribute__((section(".vector_table"), used))
void *vector_table[] = {
    &_estack,
    Reset_Handler,
    Default_Handler,  /* NMI */
    Default_Handler,  /* HardFault */
};
