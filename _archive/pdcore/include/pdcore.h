/*
 * PicoDrive 32X Debugger Core API
 *
 * Frame-perfect deterministic debugging for Sega 32X emulation
 * Supports breakpoints, memory access, CPU state inspection, and profiling
 *
 * Based on BlastEm's handler-pointer pattern for extensibility
 * All timing is cycle-based (never wall-clock) for deterministic execution
 */

#ifndef PDCORE_H
#define PDCORE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * OPAQUE EMULATOR HANDLE
 * ============================================================================
 */

typedef struct pd_t pd_t;  /* Opaque handle - implementation hidden */


/* ============================================================================
 * CPU IDENTIFIERS
 * ============================================================================
 */

typedef enum {
    PD_CPU_MASTER = 0,    /* Master SH2 (23 MHz, primary 32X CPU) */
    PD_CPU_SLAVE = 1,     /* Slave SH2 (23 MHz, secondary 32X CPU) */
    PD_CPU_68K = 2,       /* 68000 Mega Drive main CPU */
} pd_cpu_t;


/* ============================================================================
 * MEMORY BUSES
 * ============================================================================
 */

typedef enum {
    PD_BUS_SH2_ROM = 0,         /* SH2 ROM space (2000000h-23FFFFFh) */
    PD_BUS_SH2_SDRAM = 1,       /* SH2 SDRAM cached (2000000h-23FFFFFh) */
    PD_BUS_SH2_SDRAM_WT = 2,    /* SH2 SDRAM cache-through (22000000h+) */
    PD_BUS_SH2_FB = 3,          /* SH2 Frame buffers (2400000h-25FFFFFh) */
    PD_BUS_SH2_SYS = 4,         /* SH2 System registers (2A000000h+) */
    PD_BUS_68K = 5,             /* 68000 address space (000000h+) */
} pd_bus_t;

typedef struct {
    const char *name;    /* Human-readable bus name */
    uint32_t    start;   /* Starting address in bus space */
    uint32_t    size;    /* Size in bytes */
} pd_bus_info_t;


/* ============================================================================
 * STOP REASONS & EXECUTION STATE
 * ============================================================================
 */

typedef enum {
    PD_STOP_NONE = 0,              /* Still running (should not be returned) */
    PD_STOP_CYCLE_LIMIT = 1,       /* Ran out of cycles */
    PD_STOP_FRAME_BOUNDARY = 2,    /* Hit V-BLANK frame boundary */
    PD_STOP_EXEC_BREAKPOINT = 3,   /* Hit execution breakpoint */
    PD_STOP_WATCHPOINT = 4,        /* Hit memory watchpoint (P1 feature) */
    PD_STOP_EVENT = 5,             /* Hit configured event */
    PD_STOP_EXCEPTION = 6,         /* Unhandled exception */
    PD_STOP_HALT = 7,              /* Explicit halt via pd_halt() */
} pd_stop_reason_t;

typedef struct {
    pd_stop_reason_t reason;           /* Why execution stopped */
    pd_cpu_t cpu;                      /* Which CPU triggered event (if applicable) */
    uint32_t address;                  /* PC or memory address */
    uint64_t master_cycles;            /* Total Master SH2 cycles executed */
    uint64_t master_instructions;      /* Total Master SH2 instructions executed */
    uint32_t frame_number;             /* Frame number (V-BLANK count) */
} pd_stop_info_t;


/* ============================================================================
 * CPU STATE - SH2 REGISTERS
 * ============================================================================
 */

typedef struct {
    /* General purpose registers R0-R15 */
    uint32_t r[16];

    /* Special registers */
    uint32_t pc;         /* Program counter */
    uint32_t sr;         /* Status register (flags, interrupt level) */
    uint32_t pr;         /* Procedure register (return address) */
    uint32_t gbr;        /* Global base register */
    uint32_t vbr;        /* Vector base register */
    uint32_t mach;       /* Multiply-accumulate high */
    uint32_t macl;       /* Multiply-accumulate low */

    /* Debugger state (read-only, informational) */
    uint32_t cycle_count;          /* Cycles executed (relative to last reset) */
    uint32_t instruction_count;    /* Instructions executed (relative to last reset) */
    uint8_t in_delay_slot;         /* Flag: next instruction is delay slot */
    uint8_t in_interrupt;          /* Flag: executing interrupt handler */
} pd_sh2_regs_t;


/* ============================================================================
 * CONFIGURATION
 * ============================================================================
 */

typedef struct {
    int enable_trace;              /* Enable instruction tracing (P1 feature) */
    size_t trace_buffer_size;      /* Size of trace ring buffer (P1 feature) */
    int deterministic;             /* Disable RNG, use fixed seeds for reproducibility */
    int enable_watchpoints;        /* Enable memory watchpoints (P1 feature) */
} pd_config_t;


/* ============================================================================
 * BREAKPOINT SYSTEM
 * ============================================================================
 */

/* Action to take after breakpoint handler executes */
typedef enum {
    PD_BP_HALT = 0,      /* Halt execution (default) */
    PD_BP_CONTINUE = 1,  /* Continue execution */
    PD_BP_DISABLE = 2,   /* Disable this breakpoint and continue */
} pd_breakpoint_action_t;

/* Handler function called when breakpoint is hit
 * Returns: Action to take (halt, continue, or disable breakpoint)
 */
typedef pd_breakpoint_action_t (*pd_breakpoint_handler_t)(
    pd_t *emu,               /* Emulator instance */
    pd_cpu_t cpu,            /* Which CPU hit breakpoint */
    uint32_t pc,             /* Program counter at breakpoint */
    void *user_data          /* Handler-specific context (can be NULL) */
);

/* Add execution breakpoint
 * handler: function called when PC matches address
 * user_data: passed to handler (can be NULL)
 * Returns: breakpoint ID (>0) or negative error code
 */
int pd_bp_exec_add(
    pd_t *emu,
    pd_cpu_t cpu,
    uint32_t address,
    pd_breakpoint_handler_t handler,
    void *user_data
);

/* Remove execution breakpoint
 * Returns: 0 on success, negative error code on failure
 */
int pd_bp_exec_del(pd_t *emu, pd_cpu_t cpu, uint32_t address);

/* Clear all breakpoints on a CPU
 * Returns: 0 on success
 */
int pd_bp_exec_clear(pd_t *emu, pd_cpu_t cpu);

/* Check if breakpoint exists at address
 * Returns: 1 if exists, 0 if not
 */
int pd_bp_exec_exists(pd_t *emu, pd_cpu_t cpu, uint32_t address);


/* ============================================================================
 * LIFECYCLE & INITIALIZATION
 * ============================================================================
 */

/* Create emulator instance
 * config: NULL for defaults
 * Returns: opaque handle or NULL on error
 */
pd_t *pd_create(const pd_config_t *config);

/* Destroy emulator instance */
void pd_destroy(pd_t *emu);

/* Load ROM from memory buffer
 * Returns: 0 on success, <0 on error
 */
int pd_load_rom(pd_t *emu, const void *data, size_t size);

/* Load ROM from file
 * Returns: 0 on success, <0 on error
 */
int pd_load_rom_file(pd_t *emu, const char *path);

/* Reset emulation (CPU state, registers, memory)
 * Returns: 0 on success
 */
int pd_reset(pd_t *emu);


/* ============================================================================
 * EXECUTION CONTROL - DETERMINISTIC STEPPING
 * ============================================================================
 */

/* Run for N cycles on Master SH2
 * Stops on breakpoint, watchpoint, or cycle limit
 * Returns: reason why execution stopped
 */
pd_stop_reason_t pd_run_cycles(
    pd_t *emu,
    uint64_t cycles,
    pd_stop_info_t *out_stop_info
);

/* Run for N complete frames (V-BLANK to V-BLANK)
 * Frame = one V-INT period (16.67ms at 60 FPS)
 * Useful for "step one rendered frame"
 * Returns: reason why execution stopped
 */
pd_stop_reason_t pd_run_frames(
    pd_t *emu,
    uint32_t frame_count,
    pd_stop_info_t *out_stop_info
);

/* Run until condition met
 * cycle_limit: stop if total cycles exceed this (0 = no limit)
 * Returns: reason why execution stopped
 */
pd_stop_reason_t pd_run_until(
    pd_t *emu,
    uint64_t cycle_limit,
    pd_stop_info_t *out_stop_info
);

/* Single instruction step
 * Decodes instruction, sets temp breakpoint on next address,
 * resumes, returns when next address hit
 * For conditional branches: sets breakpoints on both paths
 * Returns: reason why execution stopped
 */
pd_stop_reason_t pd_step_instruction(
    pd_t *emu,
    pd_cpu_t cpu,
    pd_stop_info_t *out_stop_info
);

/* Halt execution immediately
 * Typically called from breakpoint handler
 */
void pd_halt(pd_t *emu);


/* ============================================================================
 * CPU STATE ACCESS
 * ============================================================================
 */

/* Read all SH2 registers
 * Returns: 0 on success, <0 on error
 */
int pd_get_sh2_regs(pd_t *emu, pd_cpu_t cpu, pd_sh2_regs_t *out);

/* Write SH2 registers
 * Allows debugger to modify state (e.g., for conditional breakpoints)
 * Returns: 0 on success, <0 on error
 */
int pd_set_sh2_regs(pd_t *emu, pd_cpu_t cpu, const pd_sh2_regs_t *in);

/* Read single register (convenience function)
 * reg: 0-15 for R0-R15, 16+ for special regs
 * Returns: register value
 */
uint32_t pd_get_sh2_reg(pd_t *emu, pd_cpu_t cpu, int reg);

/* Write single register
 * Returns: 0 on success, <0 on error
 */
int pd_set_sh2_reg(pd_t *emu, pd_cpu_t cpu, int reg, uint32_t value);


/* ============================================================================
 * MEMORY ACCESS (BUS-AWARE)
 * ============================================================================
 */

/* Read from specific bus
 * Returns: bytes read (may be <size if crossing boundary), or <0 on error
 */
int pd_mem_read(
    pd_t *emu,
    pd_bus_t bus,
    uint32_t address,
    void *out_buf,
    size_t size
);

/* Write to specific bus
 * Returns: bytes written, or <0 on error
 */
int pd_mem_write(
    pd_t *emu,
    pd_bus_t bus,
    uint32_t address,
    const void *data,
    size_t size
);

/* Read 32-bit word (convenience)
 * Returns: word value
 */
uint32_t pd_mem_read_u32(pd_t *emu, pd_bus_t bus, uint32_t address);

/* Write 32-bit word (convenience)
 * Returns: 0 on success, <0 on error
 */
int pd_mem_write_u32(pd_t *emu, pd_bus_t bus, uint32_t address, uint32_t value);

/* Get information about a bus (for address space validation)
 * Returns: 0 on success
 */
int pd_get_bus_info(pd_t *emu, pd_bus_t bus, pd_bus_info_t *out);

/* Allocate and return snapshot of memory region
 * Caller responsible for free()
 * Returns: pointer to allocated buffer, or NULL on error
 */
void *pd_mem_snapshot(
    pd_t *emu,
    pd_bus_t bus,
    uint32_t address,
    size_t size
);


/* ============================================================================
 * ERROR HANDLING
 * ============================================================================
 */

typedef enum {
    PD_OK = 0,
    PD_ERR_INVALID_PARAM = -1,
    PD_ERR_ROM_NOT_LOADED = -2,
    PD_ERR_OUT_OF_MEMORY = -3,
    PD_ERR_INVALID_ADDRESS = -4,
    PD_ERR_UNSUPPORTED = -5,
    PD_ERR_BREAKPOINT_LIMIT = -6,
} pd_error_t;

/* Get last error message
 * Returns: error string (may be empty if no error)
 */
const char *pd_get_error(pd_t *emu);

/* Clear error state */
void pd_clear_error(pd_t *emu);


/* ============================================================================
 * FUTURE FEATURES (P1/P2) - INTERFACES DEFINED, NOT YET IMPLEMENTED
 * ============================================================================
 */

/* Memory watchpoint support (P1 feature)
 * typedef enum {
 *     PD_WATCH_READ = 1,
 *     PD_WATCH_WRITE = 2,
 *     PD_WATCH_RW = 3,
 * } pd_watch_mode_t;
 *
 * typedef void (*pd_watchpoint_handler_t)(
 *     pd_t *emu,
 *     pd_bus_t bus,
 *     uint32_t address,
 *     uint32_t value,
 *     pd_watch_mode_t mode,
 *     void *user_data
 * );
 *
 * int pd_wp_add(...);
 * int pd_wp_del(...);
 */

/* Event system (P1 feature)
 * typedef enum {
 *     PD_EVENT_VBLANK = (1 << 0),
 *     PD_EVENT_HBLANK = (1 << 1),
 *     PD_EVENT_FRAME_END = (1 << 2),
 *     PD_EVENT_INTERRUPT = (1 << 3),
 * } pd_event_mask_t;
 */

/* Trace recording (P1-P2 feature)
 * typedef struct {
 *     uint64_t cycle;
 *     uint32_t pc;
 *     uint32_t next_pc;
 *     uint16_t opcode;
 *     uint8_t cpu;
 *     uint8_t _pad;
 * } pd_trace_record_t;
 */


#ifdef __cplusplus
}
#endif

#endif /* PDCORE_H */
