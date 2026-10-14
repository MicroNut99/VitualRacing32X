/*
 * PicoDrive Debugger Core - Breakpoint System Implementation
 *
 * Handler-pointer pattern (from BlastEm)
 * Simple O(n) linear search acceptable for <100 breakpoints
 */

#include "pdcore_bp.h"
#include <string.h>


/* ============================================================================
 * BREAKPOINT ARRAY OPERATIONS
 * ============================================================================
 */

/**
 * Initialize empty breakpoint array
 */
void pdcore_bp_init(pdcore_breakpoint_array_t *arr)
{
    if (!arr) return;

    memset(arr, 0, sizeof(pdcore_breakpoint_array_t));
    arr->count = 0;
}


/**
 * Find breakpoint at address
 * O(n) linear search - acceptable for typical debugging usage
 * Could be optimized to hash table if needed
 */
pdcore_breakpoint_t *pdcore_bp_find(pdcore_breakpoint_array_t *arr, uint32_t addr)
{
    if (!arr) return NULL;

    for (int i = 0; i < arr->count; i++) {
        if (arr->bp[i].address == addr && arr->bp[i].active) {
            return &arr->bp[i];
        }
    }

    return NULL;
}


/**
 * Add breakpoint to array
 * Returns: breakpoint ID (array index), or negative error code
 */
int pdcore_bp_add(pdcore_breakpoint_array_t *arr, uint32_t addr,
                  pd_breakpoint_handler_t handler, void *user_data)
{
    if (!arr || !handler) return -1;

    /* Check if already exists */
    if (pdcore_bp_find(arr, addr)) {
        return -2;  /* Already exists */
    }

    /* Check capacity */
    if (arr->count >= PDCORE_MAX_BREAKPOINTS) {
        return -3;  /* Array full */
    }

    /* Add new breakpoint */
    int idx = arr->count;
    arr->bp[idx].address = addr;
    arr->bp[idx].handler = handler;
    arr->bp[idx].user_data = user_data;
    arr->bp[idx].active = 1;
    arr->count++;

    return idx;
}


/**
 * Remove breakpoint from array
 * Returns: 0 on success, negative error code if not found
 */
int pdcore_bp_del(pdcore_breakpoint_array_t *arr, uint32_t addr)
{
    if (!arr) return -1;

    for (int i = 0; i < arr->count; i++) {
        if (arr->bp[i].address == addr && arr->bp[i].active) {
            /* Mark inactive (don't remove - maintain stable indices) */
            arr->bp[i].active = 0;
            return 0;
        }
    }

    return -1;  /* Not found */
}


/**
 * Clear all breakpoints
 */
void pdcore_bp_clear(pdcore_breakpoint_array_t *arr)
{
    if (!arr) return;

    for (int i = 0; i < arr->count; i++) {
        arr->bp[i].active = 0;
    }

    arr->count = 0;
}


/**
 * Count active breakpoints
 */
int pdcore_bp_count(pdcore_breakpoint_array_t *arr)
{
    if (!arr) return 0;

    int count = 0;
    for (int i = 0; i < arr->count; i++) {
        if (arr->bp[i].active) {
            count++;
        }
    }

    return count;
}
