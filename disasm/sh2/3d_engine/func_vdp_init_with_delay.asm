/*
 * VDP Initialization with Hardware Delay
 * ROM File Offset: 0x244F0 - 0x2451E (46 bytes code + 14 bytes literals)
 * SDRAM Address: 0x060044F0 - 0x0600451E (copied at boot)
 * SH2 ROM Address: 0x022244F0 - 0x0222451E
 *
 * Purpose: Initialize VDP registers with required hardware timing delays.
 *          Contains a 125-iteration delay loop that accounts for 3.18% of
 *          Slave SH2 cycles per profiling data.
 *
 * The delay loops are hardware timing requirements for VDP stability.
 * They should NOT be optimized - the VDP needs time between writes.
 *
 * Register Usage:
 *   R0  = Scratch / value to write
 *   R1  = VDP register pointer (starts at 0x3000)
 *   R2  = Offset value (0x0100)
 *   R3  = Outer loop counter (192 iterations)
 *   R7  = Delay loop counter (125 iterations)
 *   R14 = VDP register base (0x20004100)
 *
 * Profiler Hotspot:
 *   $0600450A: 3.18% of Slave cycles (delay loop DT R7)
 */

.section .text
.align 2

/* ============================================================================
 * VDP Initialization Function ($0244F0-$0244E2)
 * ============================================================================ */
func_vdp_init_delay:
    /* $0244F0: 9116 */ mov.w   @(.literal_3000,pc),r1  /* R1 = 0x3000 (VDP offset) */
    /* $0244F2: 9216 */ mov.w   @(.literal_3000,pc),r2  /* R2 = 0x3000 (same) */
    /* $0244F4: 9316 */ mov.w   @(.literal_00C0,pc),r3  /* R3 = 192 (outer loop count) */
    /* $0244F6: DE0D */ mov.l   @(.vdp_base,pc),r14     /* R14 = 0x20004100 (VDP regs) */
    /* $0244F8: 6023 */ mov     r2,r0                   /* R0 = R2 */
    /* $0244FA: 81E2 */ mov.w   r0,@(2,r14)             /* VDP_REG+2 = R0 */
    /* $0244FC: 9213 */ mov.w   @(.literal_0100,pc),r2  /* R2 = 0x0100 (step) */

.outer_loop:
    /* $0244FE: 6013 */ mov     r1,r0                   /* R0 = R1 */
    /* $024500: 81E3 */ mov.w   r0,@(3,r14)             /* VDP_REG+3 = R0 */
    /* $024502: 312C */ add     r2,r1                   /* R1 += 0x0100 */
    /* $024504: E000 */ mov     #0,r0                   /* R0 = 0 */
    /* $024506: 81E4 */ mov.w   r0,@(4,r14)             /* VDP_REG+4 = 0 */
    /* $024508: 970E */ mov.w   @(.delay_count,pc),r7   /* R7 = 125 */

.delay_loop:
    /* ────────────────────────────────────────────────────────────────────────
     * PROFILER HOTSPOT: $0600450A - 3.18% of Slave cycles
     *
     * This is a HARDWARE TIMING DELAY, not a performance bug.
     * The VDP requires time between register writes for stability.
     * DO NOT OPTIMIZE - this delay is required for correct operation.
     * ──────────────────────────────────────────────────────────────────────── */
    /* $02450A: 4710 */ dt      r7                      /* R7-- and T = (R7==0) */
    /* $02450C: 8BFD */ bf      .delay_loop             /* Loop 125 times */

.poll_loop:
    /* $02450E: E700 */ mov     #0,r7                   /* R7 = 0 */
.poll_inner:
    /* $024510: 7701 */ add     #1,r7                   /* R7++ */
    /* $024512: 85E5 */ mov.w   @(5,r14),r0             /* R0 = VDP_REG+5 (status?) */
    /* $024514: C802 */ tst     #0x02,r0                /* Test bit 1 */
    /* $024516: 8BFB */ bf      .poll_inner             /* Loop while bit set */

    /* $024518: 4310 */ dt      r3                      /* R3-- (outer counter) */
    /* $02451A: 8BF0 */ bf      .outer_loop             /* Loop 192 times */
    /* $02451C: 000B */ rts                             /* Return */
    /* $02451E: 0009 */ nop                             /* Delay slot */

/* ============================================================================
 * Literal Pool (word and longword aligned)
 * ============================================================================ */
.align 2
.literal_3000:
    /* $024520 */ .word   0x3000                        /* Initial VDP offset */
    /* $024522 */ .word   0x009F                        /* (padding/unused) */
.literal_00C0:
    /* $024524 */ .word   0x00C0                        /* Outer loop count = 192 */
.literal_0100:
    /* $024526 */ .word   0x0100                        /* Step value = 256 */
.delay_count:
    /* $024528 */ .word   0x007D                        /* Delay count = 125 */
    /* $02452A */ .word   0x0000                        /* Padding */
.align 4
.vdp_base:
    /* $02452C */ .long   0x20004100                    /* VDP register base */

/* ============================================================================
 * Analysis Notes
 *
 * This function initializes VDP registers in a triple-nested loop:
 *   - Outer loop: 192 iterations (R3)
 *   - Delay loop: 125 iterations (R7) - hardware timing requirement
 *   - Poll loop: Variable iterations - waits for VDP ready
 *
 * Total delay cycles per outer iteration: ~125 + poll time
 * Total function cycles: ~192 * (125 + poll) = significant
 *
 * The 3.18% cycle share is expected for VDP initialization during
 * mode changes or scene transitions. This is NOT a candidate for
 * optimization - the delays are hardware requirements.
 * ============================================================================ */

.global func_vdp_init_delay

/* End of func_vdp_init_with_delay.asm */
