/*
 * func_018: Quad Batch Processor — JMP Trampolines to Expansion ROM
 * ROM File Offset: 0x233A4 - 0x23413 (112 bytes)
 * SH2 Address: 0x022233A4 - 0x02223413
 *
 * S-6: Two trampolines redirecting to relocated state machine:
 *   - Main entry ($0233A4) → expansion $02301336
 *   - Alternate path ($0233F2) → expansion $0230138C
 *
 * Remaining bytes: NOP padding
 */

.section .text
.p2align 1

/* Main entry trampoline */
func_018:
    .short  0xD001                              /* $0233A4: MOV.L @(1*4,PC),R0 */
    .short  0x402B                              /* $0233A6: JMP @R0 */
    .short  0x0009                              /* $0233A8: [delay] NOP */
    .short  0x0009                              /* $0233AA: NOP (alignment) */
    .short  0x0230                              /* $0233AC: literal high ($02301336) */
    .short  0x1336                              /* $0233AE: literal low */
    /* NOP padding to alternate entry */
    .short  0x0009                              /* $0233B0 */
    .short  0x0009                              /* $0233B2 */
    .short  0x0009                              /* $0233B4 */
    .short  0x0009                              /* $0233B6 */
    .short  0x0009                              /* $0233B8 */
    .short  0x0009                              /* $0233BA */
    .short  0x0009                              /* $0233BC */
    .short  0x0009                              /* $0233BE */
    .short  0x0009                              /* $0233C0 */
    .short  0x0009                              /* $0233C2 */
    .short  0x0009                              /* $0233C4 */
    .short  0x0009                              /* $0233C6 */
    .short  0x0009                              /* $0233C8 */
    .short  0x0009                              /* $0233CA */
    .short  0x0009                              /* $0233CC */
    .short  0x0009                              /* $0233CE */
    .short  0x0009                              /* $0233D0 */
    .short  0x0009                              /* $0233D2 */
    .short  0x0009                              /* $0233D4 */
    .short  0x0009                              /* $0233D6 */
    .short  0x0009                              /* $0233D8 */
    .short  0x0009                              /* $0233DA */
    .short  0x0009                              /* $0233DC */
    .short  0x0009                              /* $0233DE */
    .short  0x0009                              /* $0233E0 */
    .short  0x0009                              /* $0233E2 */
    .short  0x0009                              /* $0233E4 */
    .short  0x0009                              /* $0233E6 */
    .short  0x0009                              /* $0233E8 */
    .short  0x0009                              /* $0233EA */
    .short  0x0009                              /* $0233EC */
    .short  0x0009                              /* $0233EE */
    .short  0x0009                              /* $0233F0 */
/* Alternate path trampoline */
.alternate_path:
    .short  0xD001                              /* $0233F2: MOV.L @(1*4,PC),R0 */
    .short  0x402B                              /* $0233F4: JMP @R0 */
    .short  0x0009                              /* $0233F6: [delay] NOP */
    .short  0x0230                              /* $0233F8: literal high ($0230138C) */
    .short  0x138C                              /* $0233FA: literal low */
    /* NOP padding to end of block */
    .short  0x0009                              /* $0233FC */
    .short  0x0009                              /* $0233FE */
    .short  0x0009                              /* $023400 */
    .short  0x0009                              /* $023402 */
    .short  0x0009                              /* $023404 */
    .short  0x0009                              /* $023406 */
    .short  0x0009                              /* $023408 */
    .short  0x0009                              /* $02340A */
    .short  0x0009                              /* $02340C */
    .short  0x0009                              /* $02340E */
    .short  0x0009                              /* $023410 */
    .short  0x0009                              /* $023412 */
