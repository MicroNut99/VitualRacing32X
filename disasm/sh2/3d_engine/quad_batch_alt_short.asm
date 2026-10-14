/*
 * func_019: Quad Batch Alternate — JMP Trampolines to Expansion ROM
 * ROM File Offset: 0x23414 - 0x2349F (140 bytes)
 * SH2 Address: 0x02223414 - 0x0222349F
 *
 * S-6: Three trampolines redirecting to relocated state machine:
 *   - Main entry ($023414) → expansion $023013CA
 *   - Helper process ($023450) → expansion $0230140A
 *   - Alternate entry ($02346A) → expansion $02301440
 *
 * Remaining bytes: NOP padding
 */

.section .text
.p2align 1

/* Main entry trampoline */
func_019:
    .short  0xD001                              /* $023414: MOV.L @(1*4,PC),R0 */
    .short  0x402B                              /* $023416: JMP @R0 */
    .short  0x0009                              /* $023418: [delay] NOP */
    .short  0x0009                              /* $02341A: NOP (alignment) */
    .short  0x0230                              /* $02341C: literal high ($023013CA) */
    .short  0x13CA                              /* $02341E: literal low */
    /* NOP padding to helper process */
    .short  0x0009                              /* $023420 */
    .short  0x0009                              /* $023422 */
    .short  0x0009                              /* $023424 */
    .short  0x0009                              /* $023426 */
    .short  0x0009                              /* $023428 */
    .short  0x0009                              /* $02342A */
    .short  0x0009                              /* $02342C */
    .short  0x0009                              /* $02342E */
    .short  0x0009                              /* $023430 */
    .short  0x0009                              /* $023432 */
    .short  0x0009                              /* $023434 */
    .short  0x0009                              /* $023436 */
    .short  0x0009                              /* $023438 */
    .short  0x0009                              /* $02343A */
    .short  0x0009                              /* $02343C */
    .short  0x0009                              /* $02343E */
    .short  0x0009                              /* $023440 */
    .short  0x0009                              /* $023442 */
    .short  0x0009                              /* $023444 */
    .short  0x0009                              /* $023446 */
    .short  0x0009                              /* $023448 */
    .short  0x0009                              /* $02344A */
    .short  0x0009                              /* $02344C */
    .short  0x0009                              /* $02344E */
/* Helper process trampoline */
.helper_process:
    .short  0xD001                              /* $023450: MOV.L @(1*4,PC),R0 */
    .short  0x402B                              /* $023452: JMP @R0 */
    .short  0x0009                              /* $023454: [delay] NOP */
    .short  0x0009                              /* $023456: NOP (alignment) */
    .short  0x0230                              /* $023458: literal high ($0230140A) */
    .short  0x140A                              /* $02345A: literal low */
    /* NOP padding to alternate entry */
    .short  0x0009                              /* $02345C */
    .short  0x0009                              /* $02345E */
    .short  0x0009                              /* $023460 */
    .short  0x0009                              /* $023462 */
    .short  0x0009                              /* $023464 */
    .short  0x0009                              /* $023466 */
    .short  0x0009                              /* $023468 */
/* Alternate entry trampoline */
.func_019_alt:
    .short  0xD001                              /* $02346A: MOV.L @(1*4,PC),R0 */
    .short  0x402B                              /* $02346C: JMP @R0 */
    .short  0x0009                              /* $02346E: [delay] NOP */
    .short  0x0230                              /* $023470: literal high ($02301440) */
    .short  0x1440                              /* $023472: literal low */
    /* NOP padding to end of block */
    .short  0x0009                              /* $023474 */
    .short  0x0009                              /* $023476 */
    .short  0x0009                              /* $023478 */
    .short  0x0009                              /* $02347A */
    .short  0x0009                              /* $02347C */
    .short  0x0009                              /* $02347E */
    .short  0x0009                              /* $023480 */
    .short  0x0009                              /* $023482 */
    .short  0x0009                              /* $023484 */
    .short  0x0009                              /* $023486 */
    .short  0x0009                              /* $023488 */
    .short  0x0009                              /* $02348A */
    .short  0x0009                              /* $02348C */
    .short  0x0009                              /* $02348E */
    .short  0x0009                              /* $023490 */
    .short  0x0009                              /* $023492 */
    .short  0x0009                              /* $023494 */
    .short  0x0009                              /* $023496 */
    .short  0x0009                              /* $023498 */
    .short  0x0009                              /* $02349A */
    .short  0x0009                              /* $02349C */
    .short  0x0009                              /* $02349E */
