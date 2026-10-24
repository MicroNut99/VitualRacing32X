/* Linker script for case_handlers - places code at correct SH2 address */
SECTIONS
{
    . = 0x23070;  /* ROM file offset 0x23070 */
    .text : SUBALIGN(2) { *(.text) }  /* Force 2-byte alignment */
}
