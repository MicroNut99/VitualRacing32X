/*
 * 2D Block Copy Function
 * ROM File Offset: 0x251B0 - 0x251F4 (68 bytes)
 * SDRAM Address: 0x060051B0 - 0x060051F4 (copied at boot)
 * SH2 ROM Address: 0x022251B0 - 0x022251F4
 *
 * Purpose: Copy 2D blocks of data (e.g., framebuffer, textures, sprites).
 *          Nested loop structure for row-by-row block transfer.
 *
 * Profiler Hotspot:
 *   $060051CA: 2.43% of Master SH2 cycles (inner copy loop)
 *
 * This is a significant CPU consumer during rendering/display operations.
 *
 * Register Usage (inferred):
 *   R0 = Destination base pointer (advances by stride each row)
 *   R1 = Words per row (divided by 2 at entry)
 *   R2 = Number of rows (outer loop counter)
 *   R3 = Source pointer (reads sequentially)
 *   R4 = Current dest pointer (within row)
 *   R5 = Words remaining in current row
 *   R6 = Row stride (0x200 = 512 bytes)
 *   R7 = Temp (word being copied)
 *   R8 = 1 (constant)
 *
 * Algorithm:
 *   for (row = 0; row < R2; row++) {
 *       dest = R0;
 *       for (word = 0; word < R1; word++) {
 *           *dest++ = *src++;
 *       }
 *       R0 += stride;  // Next row
 *   }
 */

.section .text
.align 2

/* ============================================================================
 * Entry Point / Setup ($0251B0-$0251C2)
 * Wait for something, then initialize loop variables
 * ============================================================================ */
func_block_copy_2d:
    /* $0251B0: 2561 */ mov.w   r6,@r5                  /* Write R6 to *R5 (trigger?) */
.wait_loop:
    /* $0251B2: 6751 */ mov.w   @r5,r7                  /* R7 = *R5 */
    /* $0251B4: 3760 */ cmp/eq  r6,r7                   /* R7 == R6? */
    /* $0251B6: 89FC */ bt      .wait_loop              /* Wait until different */

    /* $0251B8: D30B */ mov.l   @(.src_ptr,pc),r3       /* R3 = source pointer */
    /* $0251BA: 6332 */ mov.l   @r3,r3                  /* R3 = *R3 (indirect) */
    /* $0251BC: E600 */ mov     #0,r6                   /* R6 = 0 */
    /* $0251BE: 2561 */ mov.w   r6,@r5                  /* Clear trigger */
    /* $0251C0: 9611 */ mov.w   @(.row_stride,pc),r6    /* R6 = 0x200 (row stride) */
    /* $0251C2: E801 */ mov     #1,r8                   /* R8 = 1 (constant) */

/* ============================================================================
 * Outer Loop - Row Iterator ($0251C4-$0251D8)
 * ============================================================================ */
.row_loop:
    /* $0251C4: 4101 */ shlr    r1                      /* R1 = R1 / 2 (byte→word) */
    /* $0251C6: 6403 */ mov     r0,r4                   /* R4 = dest (row start) */
    /* $0251C8: 6513 */ mov     r1,r5                   /* R5 = words per row */

/* ============================================================================
 * Inner Loop - Word Copy ($0251CA-$0251D2)
 *
 * PROFILER HOTSPOT: $060051CA - 2.43% of Master cycles
 *
 * This tight loop copies words from source to destination.
 * Each iteration: 4 cycles minimum (load, store, dt, bf/s, add in delay)
 * ============================================================================ */
.copy_word:
    /* $0251CA: 6735 */ mov.w   @r3+,r7                 /* R7 = *src++; read word */
    /* $0251CC: 2471 */ mov.w   r7,@r4                  /* *dest = R7; write word */
    /* $0251CE: 4510 */ dt      r5                      /* R5-- and T = (R5==0) */
    /* $0251D0: 8FFB */ bf/s    .copy_word              /* Loop if R5 != 0 */
    /* $0251D2: 7402 */ add     #2,r4                   /* Delay: dest += 2 */

    /* Row complete - next row */
    /* $0251D4: 4210 */ dt      r2                      /* R2-- (row counter) */
    /* $0251D6: 8FF6 */ bf/s    .row_loop               /* Loop if rows remain */
    /* $0251D8: 306C */ add     r6,r0                   /* Delay: dest += stride */

/* ============================================================================
 * Cleanup - Call Completion Handler ($0251DA-$0251E4)
 * ============================================================================ */
    /* $0251DA: D005 */ mov.l   @(.done_handler,pc),r0  /* R0 = completion func */
    /* $0251DC: 400B */ jsr     @r0                     /* Call it */
    /* $0251DE: 0009 */ nop                             /* Delay slot */
    /* $0251E0: 4F26 */ lds.l   @r15+,pr                /* Pop PR */
    /* $0251E2: 000B */ rts                             /* Return */
    /* $0251E4: 0009 */ nop                             /* Delay slot */

/* ============================================================================
 * Literal Pool
 * ============================================================================ */
.align 2
.row_stride:
    /* $0251E6 */ .word   0x0200                        /* 512 bytes per row */
.align 4
.src_ptr:
    /* $0251E8 */ .long   0x20004028                    /* Source pointer address */
.align 4
    /* $0251EC */ .long   0x2000402C                    /* ? */
.done_handler:
    /* $0251F0 */ .long   0x060043F0                    /* Completion handler */

/* ============================================================================
 * Analysis Notes
 *
 * Performance Profile:
 *   - Inner loop: ~4 cycles per word (16-bit transfer)
 *   - Throughput: ~5.75 MB/s @ 23 MHz (theoretical maximum)
 *   - 2.43% of Master cycles indicates heavy use during rendering
 *
 * Likely Use Cases:
 *   - Framebuffer blitting
 *   - Texture upload to VDP
 *   - Sprite/tile data transfer
 *   - Double-buffer page flip
 *
 * Optimization Potential:
 *   - Could use longword (32-bit) transfers for 2x throughput
 *   - DMA might be faster for large blocks
 *   - Unrolling inner loop could save branch overhead
 *
 * The row stride of 0x200 (512 bytes = 256 pixels @ 16bpp) suggests
 * this operates on 256-pixel-wide framebuffer rows.
 * ============================================================================ */

.global func_block_copy_2d

/* End of func_block_copy_2d.asm */
