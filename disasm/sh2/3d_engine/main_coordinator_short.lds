/* Linker script for func_001 - places code at correct SH2 address */
SECTIONS
{
    . = 0x23024;  /* ROM file offset 0x23024 */
    .text : SUBALIGN(2) { *(.text) }  /* Force 2-byte alignment */
}
