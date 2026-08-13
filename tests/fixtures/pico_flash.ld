/* pico_flash.ld — minimal flash-linked RP2040 linker script.
 *
 * Places .vector_table at 0x10000000 (XIP flash base).  The RP2040
 * BOOTROM at address 0 stages the flash image: it reads the vector
 * table from 0x10000000, loads SP from word 0, and jumps to the reset
 * handler in word 1.  labwired-core's load path expects this shape.
 *
 * No boot2 (labwired handles XIP setup), no .data init, no BSS clear.
 * Suitable for small self-contained firmware that uses only registers.
 */

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x10000000, LENGTH = 2048K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 264K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    .vector_table : {
        KEEP(*(.vector_table))
    } > FLASH

    .text : {
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > FLASH

    /DISCARD/ : {
        *(.ARM.exidx*)
        *(.ARM.attributes*)
        *(.comment)
    }
}
