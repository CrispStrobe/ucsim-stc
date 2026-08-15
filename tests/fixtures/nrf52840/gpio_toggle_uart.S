/* gpio_toggle_uart.S — nRF52840 GPIO toggle with UART reporting.
 *
 * Toggles P0.13 with a counted delay, reports each edge via UART0.
 * This proves both GPIO register writes and instruction-count timing
 * under labwired's nRF52840 model.
 *
 * DELAY_COUNT = 100 (small, so we finish within max_steps budget).
 * Expected cycle arithmetic per half-period:
 *   str (OUTSET/OUTCLR):  2 cy
 *   ldr (delay count):    2 cy
 *   delay loop:           3*(DELAY_COUNT-1) + 2 = 299 cy
 *   uart send ("H\n" or "L\n"): ~variable, dominated by TXDRDY poll
 *   b (back):             2 cy
 *   ≈ 305 cy of toggle logic + UART overhead
 *
 * After 8 edges, sends "DONE\n" and halts.
 */

    .syntax unified
    .cpu    cortex-m4
    .thumb

    .equ GPIO_BASE,      0x50000000
    .equ DIRSET,         0x518
    .equ OUTSET,         0x508
    .equ OUTCLR,         0x50C
    .equ PIN_BIT,        (1 << 13)
    .equ DELAY_COUNT,    100

    .equ UART_BASE,      0x40002000
    .equ TASKS_STARTTX,  0x008
    .equ EVENTS_TXDRDY,  0x11C
    .equ ENABLE_REG,     0x500
    .equ PSELTXD,        0x50C
    .equ TXD,            0x51C
    .equ BAUDRATE,       0x524
    .equ CONFIG_REG,     0x56C
    .equ BAUD_115200,    0x01D7E000

    .section .vectors, "a", %progbits
    .word   0x20010000
    .word   _start + 1

    .text
    .thumb_func
    .global _start
_start:
    /* --- UART0 init --- */
    ldr     r6, =UART_BASE
    mov     r1, #6
    str     r1, [r6, #PSELTXD]
    ldr     r1, =BAUD_115200
    str     r1, [r6, #BAUDRATE]
    mov     r1, #0
    str     r1, [r6, #CONFIG_REG]
    mov     r1, #4
    str     r1, [r6, #ENABLE_REG]
    mov     r1, #1
    str     r1, [r6, #TASKS_STARTTX]

    /* --- GPIO P0.13 output --- */
    ldr     r0, =GPIO_BASE
    ldr     r1, =PIN_BIT
    str     r1, [r0, #DIRSET]

    mov     r7, #8              /* 8 edges (4 full toggles) */

.Ltoggle:
    /* Set P0.13 high. */
    str     r1, [r0, #OUTSET]

    /* Report "H\n" via UART. */
    mov     r2, #'H'
    bl      uart_putc
    mov     r2, #'\n'
    bl      uart_putc

    /* Delay loop. */
    ldr     r3, =DELAY_COUNT
.Ldelay_high:
    subs    r3, r3, #1
    bne     .Ldelay_high

    /* Decrement edge count. */
    subs    r7, r7, #1
    beq     .Ldone

    /* Set P0.13 low. */
    str     r1, [r0, #OUTCLR]

    /* Report "L\n" via UART. */
    mov     r2, #'L'
    bl      uart_putc
    mov     r2, #'\n'
    bl      uart_putc

    /* Delay loop. */
    ldr     r3, =DELAY_COUNT
.Ldelay_low:
    subs    r3, r3, #1
    bne     .Ldelay_low

    subs    r7, r7, #1
    beq     .Ldone
    b       .Ltoggle

.Ldone:
    /* Send "DONE\n". */
    adr     r4, msg_done
    ldr     r5, =msg_done_end
.Lsend_done:
    ldrb    r2, [r4]
    bl      uart_putc
    add     r4, #1
    cmp     r4, r5
    blt     .Lsend_done
.Lhalt:
    wfi
    b       .Lhalt

/* uart_putc: send byte in r2 via UART0 (r6 = UART_BASE). */
    .thumb_func
uart_putc:
    push    {r1, lr}
    mov     r1, #0
    str     r1, [r6, #EVENTS_TXDRDY]
    str     r2, [r6, #TXD]
.Lwait:
    ldr     r1, [r6, #EVENTS_TXDRDY]
    cmp     r1, #0
    beq     .Lwait
    pop     {r1, pc}

    .align 2
msg_done:
    .ascii  "DONE\n"
msg_done_end:
