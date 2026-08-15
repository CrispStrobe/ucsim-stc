/* Minimal linker script for bare-metal nRF52840. */
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 1024K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 256K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    .vectors : { KEEP(*(.vectors)) } > FLASH
    .text    : { *(.text .text.*) *(.rodata .rodata.*) } > FLASH
    /DISCARD/ : { *(.ARM.exidx*) *(.ARM.attributes*) *(.comment) }
}
