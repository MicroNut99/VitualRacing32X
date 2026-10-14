/*
 * PicoDrive Debugger Core - Internal Bridge
 *
 * NOT part of public API - for internal use only
 * Bridges PicoDrive's emulation state with pdcore debugger functionality
 */

#ifndef PDCORE_INTERNAL_H
#define PDCORE_INTERNAL_H

#include "pdcore.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * FORWARD DECLARATIONS - PicoDrive Types
 * ============================================================================
 */

/* Forward declare PicoDrive's internal structures
 * We don't need full definitions - just opaque pointers
 */
typedef struct SH2_ SH2;
typedef struct Genesis_State_ Genesis_State;


/* ============================================================================
 * MAIN EMULATOR STATE STRUCTURE
 * ============================================================================
 */

typedef struct pd_t {
    /* PicoDrive core state */
    Genesis_State *genesis;           /* Main Genesis/32X state */
    SH2 *master_sh2;                  /* Master SH2 CPU */
    SH2 *slave_sh2;                   /* Slave SH2 CPU */

    /* Breakpoint arrays */
    void *bp_array_master;            /* Breakpoint array for Master SH2 */
    void *bp_array_slave;             /* Breakpoint array for Slave SH2 */
    int num_breakpoints_master;       /* Current number of breakpoints (Master) */
    int num_breakpoints_slave;        /* Current number of breakpoints (Slave) */

    /* Execution state tracking */
    uint32_t frame_count;             /* V-BLANK counter (frame number) */
    uint64_t master_cycles;           /* Total Master SH2 cycles executed */
    uint64_t master_instructions;     /* Total Master SH2 instructions executed */
    uint64_t slave_cycles;            /* Total Slave SH2 cycles executed (P1) */

    /* Debugger control state */
    int halt_requested;               /* Flag: stop execution immediately */
    int running;                      /* Flag: emulation is currently running */

    /* Error handling */
    char error_buf[256];              /* Error message buffer */

    /* Configuration */
    pd_config_t config;               /* Current configuration */

} pd_t;


/* ============================================================================
 * INTERNAL FUNCTION PROTOTYPES
 * ============================================================================
 */

/* Initialize PicoDrive accessors
 * Called during pd_create()
 * Returns: 0 on success, <0 on error
 */
int pdcore_init_picodrive_accessors(pd_t *emu);

/* Attach breakpoint callback to SH2
 * Returns: 0 on success
 */
int pdcore_attach_bp_callback(pd_t *emu, pd_cpu_t cpu);

/* Attach V-BLANK callback to Genesis state
 * Returns: 0 on success
 */
int pdcore_attach_vblank_callback(pd_t *emu);

/* Check for breakpoint at PC
 * Called from SH2 execution loop (high frequency!)
 * Returns: 1 if should stop, 0 if continue
 */
int pdcore_check_breakpoint(SH2 *sh2);

/* V-BLANK event handler
 * Called when V-BLANK bit is set
 */
void pdcore_on_vblank(Genesis_State *gen);


/* ============================================================================
 * PICODRIVE ACCESSOR FUNCTIONS
 * ============================================================================
 */

/* Get PicoDrive's global Genesis state
 * These are thin wrappers over PicoDrive's internal functions
 */
Genesis_State *pdcore_get_genesis_state(void);
SH2 *pdcore_get_sh2_master(void);
SH2 *pdcore_get_sh2_slave(void);


#ifdef __cplusplus
}
#endif

#endif /* PDCORE_INTERNAL_H */
