/*
 * func_017: Quad Helper — JMP Trampoline to Expansion ROM
 * ROM File Offset: 0x2338A - 0x233A3 (26 bytes)
 * SH2 Address: 0x0222338A
 *
 * S-6: Trampoline redirecting to relocated state machine in expansion ROM
 *      at $02301300. The expansion version has coord_transform inlined.
 *
 * Original: BSR coord_transform + loop (26 bytes)
 * Now: JMP trampoline + NOP padding (26 bytes, same size)
 */

.section .text
.p2align 1

func_017:
    .short  0xD001                              /* $02338A: MOV.L @(1*4,PC),R0 */
    .short  0x402B                              /* $02338C: JMP @R0 */
    .short  0x0009                              /* $02338E: [delay] NOP */
    .short  0x0230                              /* $023390: literal high ($02301300) */
    .short  0x1300                              /* $023392: literal low */
    .short  0x0009                              /* $023394: NOP */
    .short  0x0009                              /* $023396: NOP */
    .short  0x0009                              /* $023398: NOP */
    .short  0x0009                              /* $02339A: NOP */
    .short  0x0009                              /* $02339C: NOP */
    .short  0x0009                              /* $02339E: NOP */
    .short  0x0009                              /* $0233A0: NOP */
    .short  0x0009                              /* $0233A2: NOP */
