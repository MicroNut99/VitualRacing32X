/* Linker script for master_dispatch_hook - SH2 address 0x02300050 (expansion ROM) */
SECTIONS
{
    . = 0x02300050;
    .text : SUBALIGN(2) { *(.text) }
}
