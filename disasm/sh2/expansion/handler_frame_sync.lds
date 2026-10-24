/* Linker script for handler_frame_sync - SH2 address 0x02300028 (expansion ROM) */
SECTIONS
{
    . = 0x02300028;
    .text : SUBALIGN(2) { *(.text) }
}
