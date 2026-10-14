/*
 * Slave SH2 Idle Loop - Original Implementation
 * ROM File Offset: 0x203CC - 0x203D6 (10 bytes + 4 byte literal)
 * SH2 Address: 0x020203CC - 0x020203D6
 *
 * Purpose: Slave SH2 initialization point. After boot, Slave enters
 *          this infinite loop, writing to COMM3 to signal it's alive,
 *          then spinning forever waiting for work.
 *
 * In the ORIGINAL game, Slave is activated differently - the game
 * redirects Slave to the rendering pipeline. This is just the fallback
 * idle state.
 *
 * Our expansion ROM hooks into this to redirect Slave to our
 * slave_work_wrapper which polls COMM7 for parallel work signals.
 *
 * Register Usage:
 *   R0 = Value to write (preserved from caller?)
 *   R1 = COMM3 address
 */

.section .text
.align 2

/* ============================================================================
 * Slave Idle Loop ($0203CC-$0203D6)
 * Writes R0 to COMM3, then loops forever
 * ============================================================================ */
slave_idle_loop:
    /* $0203CC: D101 */ mov.l   comm3_addr,r1           /* R1 = 0x2000402C (COMM3) */
    /* $0203CE: 2102 */ mov.l   r0,@r1                  /* COMM3 = R0 (signal alive) */
.spin_forever:
    /* $0203D0: AFFE */ bra     .spin_forever           /* Infinite loop (offset -2) */
    /* $0203D2: 0009 */ nop                             /* Delay slot */

/* ============================================================================
 * Literal Pool (4-byte aligned)
 * ============================================================================ */
.align 4
comm3_addr:
    /* $0203D4: 2000 402C */ .long 0x2000402C          /* COMM3 address */

/* ============================================================================
 * Hook Point for Expansion ROM
 *
 * Instead of spinning forever, we can redirect Slave to:
 *   slave_work_wrapper @ 0x02300200
 *
 * The hook replaces the BRA with a JMP to expansion ROM:
 *   Original: AFFE      bra .spin_forever
 *   Hooked:   A???      bra slave_redirect   (or use JMP for longer range)
 *
 * slave_redirect then jumps to 0x02300200 in expansion ROM where
 * the Slave polls COMM7 for work signals from Master.
 *
 * Work Signal Protocol:
 *   COMM7 = 0x0000: Idle (no work)
 *   COMM7 = 0x0001: Frame sync (increment COMM4)
 *   COMM7 = 0x0016: Vertex transform (call func_021_optimized)
 *
 * After completing work, Slave clears COMM7 and returns to polling.
 * ============================================================================ */

/*
 * Related Expansion Code:
 *   expansion_300000.asm: slave_work_wrapper @ $300200
 *   expansion_300000.asm: slave_test_func @ $300280
 *
 * Memory Map (Slave perspective):
 *   0x02000000 - 0x022FFFFF: Original ROM
 *   0x02300000 - 0x023FFFFF: Expansion ROM (1MB)
 *   0x06000000 - 0x0603FFFF: SDRAM (256KB)
 *   0x20004020 - 0x2000402F: COMM registers
 */
