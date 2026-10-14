# SH2 Command Dispatch System

## Overview

The Master SH2 uses a command dispatch system to receive work from the 68K processor. This system is the core of the 68K→SH2 communication pipeline.

## Architecture

```
┌─────────────────┐     COMM Registers      ┌──────────────────────┐
│      68K        │─────────────────────────│    Master SH2        │
│                 │  $A15120 (68K side)     │                      │
│ Sets COMM0 ≠ 0  │  $20004020 (SH2 side)   │  Polls COMM0         │
│ Sets COMM1 = cmd│                         │  Reads cmd from COMM1│
│                 │                         │  Dispatches via table│
└─────────────────┘                         └──────────────────────┘
                                                      │
                                                      ▼
                                            ┌──────────────────────┐
                                            │ Jump Table @ $06000780│
                                            │ 256 entries × 4 bytes │
                                            │ (handler addresses)   │
                                            └──────────────────────┘
```

## Jump Table Location

| Property | Value |
|----------|-------|
| Base Address | 0x06000780 (SDRAM) |
| Entry Count | 256 (one per command byte) |
| Entry Size | 4 bytes (32-bit handler address) |
| Total Size | 1024 bytes (0x400) |

## Command Dispatch Flow

### Master SH2 Poll Loop (0x020460-0x020476)

```asm
master_poll_loop:
    mov.l   comm_base,r8        ; R8 = 0x20004020
.poll_wait:
    mov.b   @r8,r0              ; R0 = COMM0
    cmp/eq  #0,r0               ; Is COMM0 == 0?
    bt      .poll_wait          ; Keep polling until non-zero

    mov.b   @(1,r8),r4          ; R4 = COMM1 (command byte)

.dispatch:
    shll2   r0                  ; R0 = R0 * 4 (table offset)
    mov.l   jump_table_addr,r1  ; R1 = 0x06000780
    mov.l   @(r0,r1),r0         ; R0 = table[cmd]
    jsr     @r0                 ; Call handler
    nop
    bra     master_poll_loop    ; Loop back
    nop

jump_table_addr:
    .long   0x06000780
```

### Dispatch Cycle Timing

| Step | Operation | Cycles |
|------|-----------|--------|
| 1 | Load COMM0 | 1 |
| 2 | Compare | 1 |
| 3 | Branch (if waiting) | 2 |
| **Poll total** | Per iteration | **4** |
| 4 | Load COMM1 | 1 |
| 5 | SHLL2 | 1 |
| 6 | Load table base | 1 |
| 7 | Load handler addr | 1 |
| 8 | JSR | 2 |
| **Dispatch total** | After cmd received | **6** |

## Jump Table Initialization

The jump table at 0x06000780 is populated by the 68K during system initialization. This happens before the SH2s begin their command loops.

### Initialization Sequence

1. **68K Boot**: Executes vector at 0x880004
2. **Hardware Init**: VDP, memory, etc.
3. **SH2 Program Load**: Copies SH2 code from ROM to SDRAM (0x06000000+)
4. **Jump Table Setup**: Writes handler addresses to 0x06000780-0x06000B7F
5. **SH2 Reset Release**: Sets adapter control to start SH2s

### Table Entry Format

Each entry is a 32-bit SH2 address in big-endian format:

```
Offset 0x000: table[0x00] = idle_handler
Offset 0x004: table[0x01] = init_command
Offset 0x008: table[0x02] = data_load
...
Offset 0x058: table[0x16] = vertex_transform (func_021)
...
Offset 0x3FC: table[0xFF] = (unused or error handler)
```

## Known Command Types

| Cmd | Hex | Purpose | Handler |
|-----|-----|---------|---------|
| 0 | 0x00 | Idle/NOP | Return immediately |
| 1 | 0x01 | Initialize | System setup |
| 22 | 0x16 | Vertex Transform | func_021 @ $0234C8 |
| 33 | 0x21 | Polygon Process | TBD |
| 34 | 0x22 | Rasterize | TBD |

## Expansion ROM Hook Point

The dispatch at $02046A is the primary hook point for expansion ROM features:

```asm
; Original code at $02046A:
    shll2   r0                  ; R0 = cmd * 4
    mov.l   jump_table_addr,r1  ; R1 = table base
    mov.l   @(r0,r1),r0         ; R0 = handler
    jsr     @r0                 ; Call

; Hooked version (master_dispatch_hook at $300050):
    ; Check if cmd should be intercepted
    ; If yes: redirect to expansion handler
    ; If no: fall through to original dispatch
```

### Current Hook Implementation

The expansion ROM contains `master_dispatch_hook` at $300050 that:
1. Checks if COMM1 == 0x16 (vertex transform)
2. If match: Captures parameters and signals Slave via COMM7
3. Otherwise: Delegates to original dispatch

See: [expansion_300000.asm](../sections/expansion_300000.asm)

## Performance Implications

### Polling Overhead

While waiting for the 68K, Master SH2 burns cycles in the poll loop:
- 4 cycles per poll iteration
- If 68K takes 1000 cycles: ~250 wasted poll iterations
- This is idle time that could be used for parallel work

### Hook Latency

Adding a hook check adds ~10 cycles per dispatch:
- Negligible for heavy operations (vertex transform: ~1000 cycles)
- Noticeable for lightweight commands

## Related Files

| File | Purpose |
|------|---------|
| [master_command_loop.asm](3d_engine/master_command_loop.asm) | Annotated dispatch loop |
| [expansion_300000.asm](../sections/expansion_300000.asm) | Hook implementation |
| [COMM_REGISTER_REFERENCE.md](COMM_REGISTER_REFERENCE.md) | COMM register details |

## See Also

- [SH2_ARCHITECTURE_COMPLETE.md](../analysis/sh2-analysis/SH2_ARCHITECTURE_COMPLETE.md) - Full architecture overview
- [68K_SH2_CROSS_REFERENCE.md](../analysis/68K_SH2_CROSS_REFERENCE.md) - Inter-processor communication
