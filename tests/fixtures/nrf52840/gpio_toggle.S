/* gpio_toggle.S — minimal nRF52840 bare-metal GPIO toggle.
 *
 * Clean-room from the Nordic nRF52840 Product Specification v1.1:
 *   GPIO P0 base:     0x50000000
 *   P0.DIRSET:        base + 0x518   (set pin direction to output)
 *   P0.OUTSET:        base + 0x508   (set pin high)
 *   P0.OUTCLR:        base + 0x50C   (set pin low)
 *
 * Toggles P0.13 (LED1 on the nRF52840-DK, also micro:bit V2 ROW1)
 * with a counted delay loop.  The delay loop is exactly DELAY_COUNT
 * iterations; each iteration is 3 instructions (SUBS + BNE-taken = 3 cycles,
 * BNE-not-taken = 1 so the last pass is 2 cycles).
 *
 * Total cycles per half-period:
 *   setup (LDR+STR)       ~4 cy
 *   delay loop             3 * (DELAY_COUNT - 1) + 2 cy
 *   branch back            ~2 cy
 *   ≈ 3 * DELAY_COUNT cy
 *
 * At 64 MHz (nRF52840 default after reset — no HFCLK setup needed for
 * the sim, which models Cortex-M4 at the configured clock), 500000 iters
 * → ~23.4 ms half-period.
 *
 * Assemble + link:
 *   arm-none-eabi-as -mcpu=cortex-m4 -mthumb -o gpio_toggle.o gpio_toggle.S
 *   arm-none-eabi-ld -T gpio_toggle.ld -o gpio_toggle.elf gpio_toggle.o
 */

    .syntax unified
    .cpu    cortex-m4
    .thumb

    .equ GPIO_BASE,   0x50000000
    .equ DIRSET,      0x518
    .equ OUTSET,      0x508
    .equ OUTCLR,      0x50C
    .equ PIN_BIT,     (1 << 13)        /* P0.13 */
    .equ DELAY_COUNT, 500000

    .section .vectors, "a", %progbits
    .word   0x20010000                  /* Initial SP (64 KB SRAM) */
    .word   _start + 1                  /* Reset vector (thumb) */

    .text
    .thumb_func
    .global _start
_start:
    /* Configure P0.13 as output via DIRSET. */
    ldr     r0, =GPIO_BASE
    ldr     r1, =PIN_BIT
    str     r1, [r0, #DIRSET]

.Ltoggle:
    /* Set P0.13 high. */
    str     r1, [r0, #OUTSET]

    /* Delay loop: DELAY_COUNT iterations. */
    ldr     r2, =DELAY_COUNT
.Ldelay_high:
    subs    r2, r2, #1
    bne     .Ldelay_high

    /* Set P0.13 low. */
    str     r1, [r0, #OUTCLR]

    /* Delay loop again. */
    ldr     r2, =DELAY_COUNT
.Ldelay_low:
    subs    r2, r2, #1
    bne     .Ldelay_low

    b       .Ltoggle
