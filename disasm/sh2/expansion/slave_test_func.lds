/* Linker script for slave_test_func - SH2 address 0x02300280 (expansion ROM) */
SECTIONS
{
    . = 0x02300280;
    .text : SUBALIGN(2) { *(.text) }
}
