/*
 * PicoDrive Debugger Core - Breakpoint System
 *
 * Handler-pointer pattern for extensibility (borrowed from BlastEm)
 * Multiple debuggers/profilers can coexist using same breakpoint array
 */

#ifndef PDCORE_BP_H
#define PDCORE_BP_H

#include "pdcore.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * BREAKPOINT LIMITS
 * ============================================================================
 */

#define PDCORE_MAX_BREAKPOINTS 128  /* Maximum breakpoints per CPU */


/* ============================================================================
 * BREAKPOINT DATA STRUCTURE
 * ============================================================================
 */

typedef struct {
    uint32_t address;                    /* CPU address of breakpoint */
    pd_breakpoint_handler_t handler;     /* Handler callback function */
    void *user_data;                     /* Context passed to handler */
    int active;                          /* 1 if active, 0 if inactive */
} pdcore_breakpoint_t;

/* Array of breakpoints for a single CPU */
typedef struct {
    pdcore_breakpoint_t bp[PDCORE_MAX_BREAKPOINTS];
    int count;                           /* Current number of breakpoints */
} pdcore_breakpoint_array_t;


/* ============================================================================
 * BREAKPOINT ARRAY OPERATIONS
 * ============================================================================
 */

/* Initialize breakpoint array
 * Called once per CPU during emulator creation
 */
void pdcore_bp_init(pdcore_breakpoint_array_t *arr);

/* Find breakpoint at address
 * Returns: pointer to breakpoint structure, or NULL if not found
 * Fast O(n) search - acceptable for <100 breakpoints
 */
pdcore_breakpoint_t *pdcore_bp_find(
    pdcore_breakpoint_array_t *arr,
    uint32_t addr
);

/* Add breakpoint to array
 * Returns: breakpoint ID (index), or negative error code
 */
int pdcore_bp_add(
    pdcore_breakpoint_array_t *arr,
    uint32_t addr,
    pd_breakpoint_handler_t handler,
    void *user_data
);

/* Remove breakpoint from array
 * Returns: 0 on success, negative error code if not found
 */
int pdcore_bp_del(pdcore_breakpoint_array_t *arr, uint32_t addr);

/* Clear all breakpoints in array */
void pdcore_bp_clear(pdcore_breakpoint_array_t *arr);

/* Get number of active breakpoints */
int pdcore_bp_count(pdcore_breakpoint_array_t *arr);


/* ============================================================================
 * IMPLEMENTATION NOTES
 * ============================================================================
 *
 * DESIGN:
 *   - Single array per CPU (Master, Slave, 68K)
 *   - Handler pointer allows different behaviors:
 *     * GDB remote debugger
 *     * Console debugger
 *     * Performance profiler
 *     * Custom tools
 *   - No special lock/mutex needed (single-threaded MVP-1)
 *
 * PERFORMANCE:
 *   - Array lookup is O(n) where n = number of breakpoints
 *   - Acceptable for n < 100 (typical debugging use case)
 *   - Could be optimized to hash table or sorted binary search if needed
 *
 * CALLING FREQUENCY:
 *   - pdcore_bp_find() called once per instruction (23 MHz)
 *   - Must be extremely fast or use unlikely() macro on check
 *
 * HANDLER SEMANTICS:
 *   - Handler called when breakpoint address is reached
 *   - Handler may inspect CPU state, modify registers, etc.
 *   - Handler calls pd_halt() to stop execution
 *   - Execution continues if handler returns normally
 *
 */


#ifdef __cplusplus
}
#endif

#endif /* PDCORE_BP_H */
