/*
 * pico_blink_probe.c — RP2040 blink + serial self-timestamping probe.
 *
 * Toggles GP25 (Pico onboard LED) every 500 ms and prints bw_now_ms()
 * over UART0.  Exercises both GPIO edges (SIO output latch) and serial
 * output — the two legs of the canonical trace format.
 *
 * Flash-linked at 0x10000000 for labwired-core.
 * SRAM variant built separately for rp2040js.
 *
 * Build (flash):
 *   arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -nostdlib -Os \
 *     -T tests/fixtures/pico_flash.ld -o tests/fixtures/pico_blink_probe.elf \
 *     tests/fixtures/pico_blink_probe.c
 *
 * Build (SRAM):
 *   arm-none-eabi-gcc -mcpu=cortex-m0plus -mthumb -nostdlib -Os \
 *     -T tests/fixtures/pico_sram.ld -o tests/fixtures/pico_blink_probe_sram.elf \
 *     tests/fixtures/pico_blink_probe.c
 *   arm-none-eabi-objcopy -O binary pico_blink_probe_sram.elf pico_blink_probe_sram.bin
 */

#include <stdint.h>

/* ── Peripheral bases ── */
#define RESETS_BASE       0x4000C000u
#define CLOCKS_BASE       0x40008000u
#define IO_BANK0_BASE     0x40014000u
#define UART0_BASE        0x40034000u
#define TIMER_BASE        0x40054000u
#define SIO_BASE          0xD0000000u

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

/* ── IO_BANK0 ── */
#define GPIO0_CTRL         (*(volatile uint32_t *)(IO_BANK0_BASE + 0x04))
#define GPIO25_CTRL        (*(volatile uint32_t *)(IO_BANK0_BASE + 0x04 + 25 * 8))
#define GPIO_FUNC_UART     2u
#define GPIO_FUNC_SIO      5u

/* ── UART0 (PL011) ── */
#define UART0_DR           (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART0_FR           (*(volatile uint32_t *)(UART0_BASE + 0x18))
#define UART0_IBRD         (*(volatile uint32_t *)(UART0_BASE + 0x24))
#define UART0_FBRD         (*(volatile uint32_t *)(UART0_BASE + 0x28))
#define UART0_LCR_H        (*(volatile uint32_t *)(UART0_BASE + 0x2C))
#define UART0_CR           (*(volatile uint32_t *)(UART0_BASE + 0x30))
#define FR_TXFF            (1u << 5)
#define UART_IBRD_VAL      3u
#define UART_FBRD_VAL      34u
#define LCR_H_8N1_FIFO    ((3u << 5) | (1u << 4))
#define CR_UARTEN_TXE     ((1u << 0) | (1u << 8))

/* ── TIMER ── */
#define TIMELR  (*(volatile uint32_t *)(TIMER_BASE + 0x0C))
#define TIMEHR  (*(volatile uint32_t *)(TIMER_BASE + 0x10))

/* ── SIO GPIO ── */
#define GPIO_OE_SET        (*(volatile uint32_t *)(SIO_BASE + 0x024))
#define GPIO_OUT_XOR       (*(volatile uint32_t *)(SIO_BASE + 0x01C))
#define GPIO_OUT_SET       (*(volatile uint32_t *)(SIO_BASE + 0x014))
#define GPIO_OUT_CLR       (*(volatile uint32_t *)(SIO_BASE + 0x018))

#define PIN25              (1u << 25)

static void uart0_putc(char c) {
    while (UART0_FR & FR_TXFF) {}
    UART0_DR = (uint32_t)c;
}

static void uart0_puts(const char *s) {
    while (*s) uart0_putc(*s++);
}

static void uart0_print_u32(uint32_t v) {
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

static uint32_t bw_now_ms(void) {
    uint32_t lo = TIMELR;
    (void)TIMEHR;
    uint32_t ms = 0;
    while (lo >= 1000u) { lo -= 1000u; ms++; }
    return ms;
}

static void init(void) {
    uint32_t bits = RESETS_UART0 | RESETS_IO_BANK0 | RESETS_PADS_BANK0 | RESETS_TIMER;
    RESETS_RESET &= ~bits;
    while ((RESETS_RESET_DONE & bits) != bits) {}

    CLK_PERI_CTRL |= CLK_PERI_ENABLE;

    /* GP0 → UART0 TX */
    GPIO0_CTRL = GPIO_FUNC_UART;

    /* GP25 → SIO (GPIO output for LED) */
    GPIO25_CTRL = GPIO_FUNC_SIO;
    GPIO_OE_SET = PIN25;
    GPIO_OUT_CLR = PIN25;  /* start OFF */

    /* UART0: 115200 8N1 */
    UART0_IBRD = UART_IBRD_VAL;
    UART0_FBRD = UART_FBRD_VAL;
    UART0_LCR_H = LCR_H_8N1_FIFO;
    UART0_CR = CR_UARTEN_TXE;
}

void main(void) {
    init();

    uint32_t deadline_ms = 500;
    const uint32_t horizon_ms = 3000;

    while (deadline_ms <= horizon_ms) {
        while (bw_now_ms() < deadline_ms) {}

        /* Toggle GP25 (LED) */
        GPIO_OUT_XOR = PIN25;

        /* Print self-timestamp */
        uart0_print_u32(bw_now_ms());
        uart0_putc('\n');

        deadline_ms += 500;
    }

    uart0_puts("DONE\n");
    while (1) { __asm volatile("wfi"); }
}

/* ── Cortex-M0+ startup ── */
extern unsigned long _estack;

__attribute__((section(".text.entry"), naked, noreturn))
void Reset_Handler(void) {
    __asm volatile(
        "ldr r0, =_estack\n"
        "mov sp, r0\n"
        "bl main\n"
        "b .\n"
    );
}

__attribute__((weak))
void Default_Handler(void) { while (1) {} }

__attribute__((section(".vector_table"), used))
void *vector_table[] = {
    &_estack,
    Reset_Handler,
    Default_Handler,
    Default_Handler,
};
