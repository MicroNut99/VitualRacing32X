/* Linker script for queue_processor - SH2 address 0x02300C00 (expansion ROM) */
SECTIONS
{
    . = 0x02300C00;
    .text : SUBALIGN(2) { *(.text) }
}
