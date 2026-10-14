/*
 * Display State Machine with Memory Copy
 * ROM File Offset: 0x239F0 - 0x23A70 (128 bytes)
 * SDRAM Address: 0x060039F0 - 0x06003A70 (copied at boot)
 * SH2 ROM Address: 0x022239F0 - 0x02223A70
 *
 * Purpose: Display/rendering state machine that:
 *          1. Calls subroutines for rendering setup
 *          2. Polls VDP status bits
 *          3. Copies data to mystery $C0000000 region
 *          4. Contains short delay loops for timing
 *
 * Profiler Hotspot:
 *   $06003A4A: 1.48% of Slave cycles (16-iteration delay loop)
 *
 * Register Usage:
 *   R0  = Scratch / status / return values
 *   R1  = Address pointer / status byte
 *   R2  = Data for copy
 *   R7  = Loop counter
 *   R14 = Context pointer (RenderingContext)
 *   R15 = Stack pointer
 *   PR  = Return address (saved/restored)
 */

.section .text
.align 2

/* ============================================================================
 * Main Entry Point ($0239F0)
 * Orchestrates rendering/display setup with subroutine calls
 * ============================================================================ */
func_display_state_machine:
    /* $0239F0: 4F22 */ sts.l   pr,@-r15                /* Save return address */
    /* $0239F2: D00E */ mov.l   @(.subroutine_1,pc),r0  /* R0 = $060045CC */
    /* $0239F4: 400B */ jsr     @r0                     /* Call subroutine 1 */
    /* $0239F6: 0009 */ nop                             /* Delay slot */
    /* $0239F8: B02B */ bsr     .memory_copy_routine    /* Call memory copy */
    /* $0239FA: 0009 */ nop                             /* Delay slot */
    /* $0239FC: BFD8 */ bsr     $022239B0               /* Call another sub */
    /* $0239FE: 0009 */ nop                             /* Delay slot */

.state_loop:
    /* $023A00: D00B */ mov.l   @(.literal_2000,pc),r0  /* R0 = 0x20000000 */
    /* $023A02: 51E9 */ mov.l   @(0x24,r14),r1          /* R1 = context+0x24 */
    /* $023A04: 210B */ or      r0,r1                   /* R1 |= 0x20000000 */
.poll_status:
    /* $023A06: 851E */ mov.w   @(0x0E,r1),r0           /* R0 = status word */
    /* $023A08: C804 */ tst     #0x04,r0                /* Test bit 2 */
    /* $023A0A: 891D */ bt      .short_delay            /* If clear, delay */
    /* $023A0C: C802 */ tst     #0x02,r0                /* Test bit 1 */
    /* $023A0E: 8B13 */ bf      .alt_path               /* If set, alt path */

    /* Main path - call subroutine with context */
    /* $023A10: D008 */ mov.l   @(.subroutine_2,pc),r0  /* R0 = $C0000000 */
    /* $023A12: 400B */ jsr     @r0                     /* Call it */
    /* $023A14: 2FE6 */ mov.l   r14,@-r15               /* Delay: push R14 */
    /* $023A16: 6EF6 */ mov.l   @r15+,r14               /* Pop R14 */
    /* $023A18: 51E9 */ mov.l   @(0x24,r14),r1          /* R1 = context+0x24 */
    /* $023A1A: E008 */ mov     #0x08,r0                /* R0 = 8 */
    /* $023A1C: 811E */ mov.w   r0,@(0x0E,r1)           /* Write status */
    /* $023A1E: 9004 */ mov.w   @(.mask_value,pc),r0    /* R0 = mask */
    /* $023A20: 51E9 */ mov.l   @(0x24,r14),r1          /* R1 = context+0x24 */
    /* $023A22: 7140 */ add     #0x40,r1                /* R1 += 64 */
    /* $023A24: 2109 */ and     r0,r1                   /* R1 &= mask */
    /* $023A26: AFEB */ bra     .state_loop             /* Loop back */
    /* $023A28: 1E19 */ mov.l   r1,@(0x24,r14)          /* Delay: save R1 */

/* ============================================================================
 * Literal Pool 1
 * ============================================================================ */
.align 4
.subroutine_1:
    /* $023A2C */ .long   0x060045CC                    /* Init subroutine */
.literal_2000:
    /* $023A30 */ .long   0x20000000                    /* Cache-through bit */
.subroutine_2:
    /* $023A34 */ .long   0xC0000000                    /* Mystery subroutine? */

/* ============================================================================
 * Alternate Path ($023A38)
 * ============================================================================ */
.alt_path:
    /* $023A38: 9003 */ mov.w   @(.alt_value,pc),r0     /* R0 = 0xAB00 */
    /* $023A3A: 811E */ mov.w   r0,@(0x0E,r1)           /* Write status */
    /* $023A3C: D001 */ mov.l   @(.jump_target,pc),r0   /* R0 = $0600442C */
    /* $023A3E: 402B */ jmp     @r0                     /* Jump (tail call) */
    /* $023A40: 4F26 */ lds.l   @r15+,pr                /* Delay: pop PR */

.alt_value:
    /* $023A42 */ .word   0xAB00
.jump_target:
    /* $023A44 */ .long   0x0600442C

/* ============================================================================
 * Short Delay ($023A48-$023A50)
 *
 * PROFILER HOTSPOT: $06003A4A - 1.48% of Slave cycles
 *
 * 16-iteration delay loop. This is for hardware timing,
 * likely allowing VDP operations to complete.
 * ============================================================================ */
.short_delay:
    /* $023A48: E710 */ mov     #16,r7                  /* R7 = 16 */
.delay_spin:
    /* $023A4A: 4710 */ dt      r7                      /* R7-- and T = (R7==0) */
    /* $023A4C: 8BFD */ bf      .delay_spin             /* Loop 16 times */
    /* $023A4E: AFDA */ bra     .poll_status            /* Return to polling */
    /* $023A50: 0009 */ nop                             /* Delay slot */

/* ============================================================================
 * Memory Copy Routine ($023A52-$023A64)
 *
 * Copies 145 longwords (580 bytes) from SDRAM to $C0000000.
 * The $C0000000 destination is an undocumented/non-standard address.
 * ============================================================================ */
.memory_copy_routine:
    /* $023A52: D105 */ mov.l   @(.copy_dest,pc),r1     /* R1 = 0xC0000000 */
    /* $023A54: D005 */ mov.l   @(.copy_src,pc),r0      /* R0 = 0x06003A70 */
    /* $023A56: 9706 */ mov.w   @(.copy_count,pc),r7    /* R7 = 145 */
.copy_loop:
    /* $023A58: 6206 */ mov.l   @r0+,r2                 /* R2 = *src++ */
    /* $023A5A: 2122 */ mov.l   r2,@r1                  /* *dest = R2 */
    /* $023A5C: 4710 */ dt      r7                      /* R7-- */
    /* $023A5E: 8FFB */ bf/s    .copy_loop              /* Loop 145 times */
    /* $023A60: 7104 */ add     #4,r1                   /* Delay: dest += 4 */
    /* $023A62: 000B */ rts                             /* Return */
    /* $023A64: 0009 */ nop                             /* Delay slot */

/* ============================================================================
 * Literal Pool 2
 * ============================================================================ */
.align 2
.copy_count:
    /* $023A66 */ .word   0x0091                        /* 145 longwords */
.align 4
.copy_dest:
    /* $023A68 */ .long   0xC0000000                    /* Mystery destination */
.copy_src:
    /* $023A6C */ .long   0x06003A70                    /* SDRAM source */

/* ============================================================================
 * Analysis Notes
 *
 * This function is part of the display/rendering pipeline:
 * 1. Calls initialization subroutines
 * 2. Copies 580 bytes to $C0000000 (purpose unknown)
 * 3. Polls VDP status in a loop
 * 4. Uses short delays for hardware timing
 *
 * The $C0000000 addresses are documented as "Unknown" in DATA_STRUCTURES.md.
 * They may be:
 * - Undocumented hardware alias
 * - Special cache mode addresses
 * - Emulator-specific behavior
 *
 * The delay loop is a hardware timing requirement, not a bug.
 * ============================================================================ */

.global func_display_state_machine
.global memory_copy_routine

/* End of func_display_state_machine.asm */
