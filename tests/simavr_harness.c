/*
 * simavr_harness.c — differential-oracle harness for simavr (LGPL).
 *
 * Loads an ATmega328P hex, runs for a bounded number of cycles,
 * and reports:
 *   - PORTB pin edges with cycle timestamps
 *   - UART TX bytes with cycle timestamps
 *   - Final cycle count
 *
 * Build: gcc -O2 -o simavr_harness tests/simavr_harness.c \
 *            -lsimavr -lsimavrparts -lelf -lm
 * Usage: ./simavr_harness <hex-file> <max-cycles> [freq-hz]
 *
 * This file is part of the ucsim-stc oracle test suite. simavr itself
 * is LGPL-2.1+ and is linked dynamically — it is NOT vendored.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <simavr/sim_avr.h>
#include <simavr/avr_ioport.h>
#include <simavr/avr_uart.h>
#include <simavr/sim_hex.h>
#include <simavr/sim_io.h>

/* Max events we record */
#define MAX_EVENTS 4096

typedef struct {
    uint64_t cycle;
    char     type;      /* 'P' = pin edge, 'U' = UART byte */
    uint8_t  pin;       /* pin number (for PORTB: 0-7) */
    uint8_t  value;     /* pin state or UART byte */
} event_t;

static event_t events[MAX_EVENTS];
static int     event_count = 0;
static uint8_t last_portb = 0;

static avr_t *g_avr = NULL;

static void record_event(char type, uint8_t pin, uint8_t value) {
    if (event_count >= MAX_EVENTS) return;
    events[event_count].cycle = g_avr->cycle;
    events[event_count].type  = type;
    events[event_count].pin   = pin;
    events[event_count].value = value;
    event_count++;
}

/* Called when PORTB output changes */
static void portb_hook(avr_irq_t *irq, uint32_t value, void *param) {
    uint8_t portb = (uint8_t)(value & 0xFF);
    uint8_t changed = portb ^ last_portb;
    for (int i = 0; i < 8; i++) {
        if (changed & (1 << i)) {
            record_event('P', i, (portb >> i) & 1);
        }
    }
    last_portb = portb;
}

/* Called when UART sends a byte */
static void uart_hook(avr_irq_t *irq, uint32_t value, void *param) {
    record_event('U', 0, (uint8_t)(value & 0xFF));
}

static void usage(const char *prog) {
    fprintf(stderr, "Usage: %s <hex-file> <max-cycles> [freq-hz]\n", prog);
    fprintf(stderr, "  freq-hz defaults to 16000000 (16 MHz)\n");
    exit(1);
}

int main(int argc, char **argv) {
    if (argc < 3) usage(argv[0]);

    const char *hex_file = argv[1];
    uint64_t max_cycles = strtoull(argv[2], NULL, 0);
    uint32_t freq = (argc > 3) ? (uint32_t)strtoul(argv[3], NULL, 0) : 16000000;

    /* Load hex file */
    uint32_t fsize = 0, fbase = 0;
    uint8_t *firmware = read_ihex_file(hex_file, &fsize, &fbase);
    if (!firmware) {
        fprintf(stderr, "ERROR: cannot read %s\n", hex_file);
        return 1;
    }
    fprintf(stderr, "Loaded %u bytes from %s (base 0x%04x)\n", fsize, hex_file, fbase);

    /* Create ATmega328P */
    avr_t *avr = avr_make_mcu_by_name("atmega328p");
    if (!avr) {
        fprintf(stderr, "ERROR: cannot create atmega328p\n");
        return 1;
    }
    avr_init(avr);
    avr->frequency = freq;
    g_avr = avr;

    /* Load firmware into flash */
    memcpy(avr->flash + fbase, firmware, fsize);
    avr->pc = fbase;
    avr->codeend = fbase + fsize;
    free(firmware);

    /* Hook PORTB output (pin-all register) */
    avr_irq_t *portb_irq = avr_io_getirq(avr,
        AVR_IOCTL_IOPORT_GETIRQ('B'), IOPORT_IRQ_REG_PORT);
    if (portb_irq) {
        avr_irq_register_notify(portb_irq, portb_hook, NULL);
    } else {
        fprintf(stderr, "WARNING: could not hook PORTB\n");
    }

    /* Hook UART0 output */
    avr_irq_t *uart_irq = avr_io_getirq(avr,
        AVR_IOCTL_UART_GETIRQ('0'), UART_IRQ_OUTPUT);
    if (uart_irq) {
        avr_irq_register_notify(uart_irq, uart_hook, NULL);
    } else {
        fprintf(stderr, "WARNING: could not hook UART0\n");
    }

    /* Run */
    uint64_t start_cycle = avr->cycle;
    while ((avr->cycle - start_cycle) < max_cycles) {
        int state = avr_run(avr);
        if (state == cpu_Done || state == cpu_Crashed) {
            fprintf(stderr, "CPU state: %s at cycle %lu\n",
                state == cpu_Done ? "done" : "crashed",
                (unsigned long)avr->cycle);
            break;
        }
    }

    /* Output results */
    printf("SIMAVR_CYCLES=%lu\n", (unsigned long)avr->cycle);
    printf("SIMAVR_FREQ=%u\n", freq);
    printf("SIMAVR_EVENTS=%d\n", event_count);

    for (int i = 0; i < event_count; i++) {
        if (events[i].type == 'P') {
            uint64_t ns = (uint64_t)((double)events[i].cycle * 1e9 / freq);
            printf("PIN_EDGE cy=%lu ns=%lu portb.%d=%d\n",
                (unsigned long)events[i].cycle, (unsigned long)ns,
                events[i].pin, events[i].value);
        } else {
            uint64_t ns = (uint64_t)((double)events[i].cycle * 1e9 / freq);
            printf("UART_TX cy=%lu ns=%lu byte=0x%02x '%c'\n",
                (unsigned long)events[i].cycle, (unsigned long)ns,
                events[i].value,
                (events[i].value >= 0x20 && events[i].value < 0x7f)
                    ? events[i].value : '.');
        }
    }

    avr_terminate(avr);
    return 0;
}
