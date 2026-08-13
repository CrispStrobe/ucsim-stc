/* pico_sram.ld — SRAM-linked RP2040 linker script for rp2040js.
 *
 * Everything at 0x20000000.  rp2040js loads raw code there and sets
 * PC to 0x20000001 (Thumb).  No bootrom, no vector table needed.
 */

MEMORY
{
    RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 264K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    .text : {
        *(.text.entry)
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > RAM

    /DISCARD/ : {
        *(.vector_table)
        *(.ARM.exidx*)
        *(.ARM.attributes*)
        *(.comment)
    }
}
