/* Linker script for shadow_path_wrapper - SH2 address 0x02300400 (expansion ROM) */
SECTIONS
{
    . = 0x02300400;
    .text : SUBALIGN(2) { *(.text) }
}
