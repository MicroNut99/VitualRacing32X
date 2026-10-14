/*
 * func_021: Vertex Transform — JMP Trampoline to Expansion ROM
 * ROM File Offset: 0x234C8 - 0x234ED (38 bytes)
 * SH2 Address: 0x022234C8 - 0x022234ED
 *
 * Purpose: Trampoline that redirects to the optimized version in expansion ROM
 *          at $023011E0 (vertex_transform_optimized). The optimized version has
 *          coord_transform (func_016) inlined, eliminating BSR/RTS overhead.
 *
 * Original: BSR func_016 + vertex loop (38 bytes)
 * Now: JMP trampoline (38 bytes, same size)
 *
 * Savings: ~6 cycles/call × 800 polygons = ~4,800 cycles/frame
 *
 * Note: R0 is safe to clobber — the optimized function's inlined
 *       coord_transform body overwrites R0 immediately.
 */

.section .text
.p2align 1    /* 2-byte alignment for 0x234C8 start */

/* ═══════════════════════════════════════════════════════════════════════════
 * func_021: JMP Trampoline → expansion ROM $023011E0
 * Entry: 0x022234C8
 *
 * Encoding: MOV.L @(1*4,PC),R0 → EA = ($0234CC & ~3) + 4 = $0234D0
 *           JMP @R0 → jumps to $023011E0
 *           NOP (delay slot)
 * ═══════════════════════════════════════════════════════════════════════════ */
func_021:
    .short  0xD001                              /* $0234C8: MOV.L @(1*4,PC),R0 */
    .short  0x402B                              /* $0234CA: JMP @R0 */
    .short  0x0009                              /* $0234CC: [delay] NOP */
    .short  0x0009                              /* $0234CE: NOP (alignment padding) */
    /* Literal pool (4-byte aligned at $0234D0) */
    .short  0x0230                              /* $0234D0: target high ($023011E0) */
    .short  0x11E0                              /* $0234D2: target low */
    /* Remaining space: NOP padding */
    .short  0x0009                              /* $0234D4: NOP */
    .short  0x0009                              /* $0234D6: NOP */
    .short  0x0009                              /* $0234D8: NOP */
    .short  0x0009                              /* $0234DA: NOP */
    .short  0x0009                              /* $0234DC: NOP */
    .short  0x0009                              /* $0234DE: NOP */
    .short  0x0009                              /* $0234E0: NOP */
    .short  0x0009                              /* $0234E2: NOP */
    .short  0x0009                              /* $0234E4: NOP */
    .short  0x0009                              /* $0234E6: NOP */
    .short  0x0009                              /* $0234E8: NOP */
    .short  0x0009                              /* $0234EA: NOP */
    .short  0x0009                              /* $0234EC: NOP */

/* ============================================================================
 * End of func_021 trampoline (38 bytes = 19 words)
 * Target: vertex_transform_optimized at expansion ROM $023011E0
 * ============================================================================ */
