/*
 * pico_crt0.c — Cortex-M0+ startup for flash-linked RP2040 firmware.
 *
 * Provides the vector table at 0x10000000 and a reset handler that
 * sets SP and calls main().  Linked with the generated C from
 * sb3-creator's generateC for the labwired-core flash-load path.
 *
 * No BSS clear, no .data init — generateC output uses only registers
 * and stack-local variables.
 */
extern unsigned long _estack;
extern unsigned long __bss_start;
extern unsigned long __bss_end;
extern int main(void);

__attribute__((optimize("no-tree-loop-distribute-patterns")))
void zero_bss(void) {
    volatile unsigned long *p = (volatile unsigned long *)&__bss_start;
    while (p < &__bss_end) *p++ = 0;
}

__attribute__((naked, noreturn))
void Reset_Handler(void) {
    __asm volatile(
        "ldr r0, =_estack\n"
        "mov sp, r0\n"
        "bl zero_bss\n"
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
    Default_Handler,  /* NMI */
    Default_Handler,  /* HardFault */
};
