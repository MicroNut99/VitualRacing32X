/* Linker script for cmdint_handler - SH2 address 0x02300800 (expansion ROM) */
SECTIONS
{
    . = 0x02300800;
    .text : SUBALIGN(2) { *(.text) }
}
