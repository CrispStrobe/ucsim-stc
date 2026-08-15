/* uart_hello.S — minimal nRF52840 bare-metal UART TX test.
 *
 * Clean-room from the Nordic nRF52840 Product Specification v1.1:
 *   UART0 base:          0x40002000
 *   TASKS_STARTTX:       base + 0x008  (write 1 to start TX)
 *   EVENTS_TXDRDY:       base + 0x11C  (TX ready event)
 *   PSELTXD:             base + 0x50C  (TX pin select)
 *   TXD:                 base + 0x51C  (TX data register)
 *   BAUDRATE:            base + 0x524
 *   CONFIG:              base + 0x56C
 *   ENABLE:              base + 0x500  (4 = enable)
 *
 * Sends "nRF52840 OK\n" on UART0 TX (pin P0.6, typical DK wiring).
 * labwired's nRF52840_uart model captures TX output on stdout.
 */

    .syntax unified
    .cpu    cortex-m4
    .thumb

    .equ UART_BASE,      0x40002000
    .equ TASKS_STARTTX,  0x008
    .equ EVENTS_TXDRDY,  0x11C
    .equ ENABLE,         0x500
    .equ PSELTXD,        0x50C
    .equ TXD,            0x51C
    .equ BAUDRATE,       0x524
    .equ CONFIG,         0x56C
    .equ BAUD_115200,    0x01D7E000
    .equ GPIO_BASE,      0x50000000
    .equ DIRSET,         0x518

    .section .vectors, "a", %progbits
    .word   0x20010000          /* Initial SP */
    .word   _start + 1          /* Reset vector (thumb) */

    .text
    .thumb_func
    .global _start
_start:
    /* Configure P0.6 as output (TX pin). */
    ldr     r0, =GPIO_BASE
    mov     r1, #(1 << 6)
    str     r1, [r0, #DIRSET]

    /* Configure UART0. */
    ldr     r0, =UART_BASE
    mov     r1, #6              /* Pin P0.6 for TX */
    str     r1, [r0, #PSELTXD]
    ldr     r1, =BAUD_115200
    str     r1, [r0, #BAUDRATE]
    mov     r1, #0              /* 8N1, no flow control */
    str     r1, [r0, #CONFIG]
    mov     r1, #4              /* Enable UART */
    str     r1, [r0, #ENABLE]
    mov     r1, #1
    str     r1, [r0, #TASKS_STARTTX]

    /* Send "nRF52840 OK\n" one byte at a time. */
    adr     r4, message
    ldr     r5, =message_end
.Lsend_loop:
    cmp     r4, r5
    bge     .Ldone

    /* Clear TXDRDY event. */
    mov     r1, #0
    str     r1, [r0, #EVENTS_TXDRDY]

    /* Write byte to TXD. */
    ldrb    r1, [r4]
    str     r1, [r0, #TXD]
    add     r4, r4, #1

    /* Wait for TXDRDY. */
.Lwait_tx:
    ldr     r1, [r0, #EVENTS_TXDRDY]
    cmp     r1, #0
    beq     .Lwait_tx

    b       .Lsend_loop

.Ldone:
    /* Halt — WFI loop. */
.Lhalt:
    wfi
    b       .Lhalt

    .align 2
message:
    .ascii  "nRF52840 OK\n"
message_end:
    .byte   0
