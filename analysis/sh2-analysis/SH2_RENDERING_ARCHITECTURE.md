# SH2 Rendering Architecture — Deep Trace (March 2026)

## Overview

VRD has **two rendering pipelines** running on the Slave SH2:

1. **On-chip SRAM pipeline** ($C0000000, 1,748 bytes): Self-contained, zero-wait-state. Handles entity polygon rendering. 77 internal BSR calls, ZERO external SDRAM calls.

2. **SDRAM cache pipeline** (main_coordinator → quad_batch → frustum_cull → coord_transform → render_quad → span_filler): Handles additional geometry via display list dispatch. THIS is where the profiled hotspots come from (37% of Slave budget).

## CPU Role Assignment (Verified)

| CPU | Dispatch | Role | Utilization |
|-----|----------|------|-------------|
| **Master SH2** | $06000460 (COMM0_HI) | Command router + block copies (cmd $22) | 0-36% |
| **Slave SH2** | $06000592 (COMM2_HI) | ALL 3D rendering (both pipelines) | 78% |
| **68K** | Main loop $FF0000 | Game logic + COMM command submission | 48% |

Master boot: $06000004 → init → dispatch at $06000460.
Slave boot: $06002004 → init at $06000570 → dispatch at $06000592.

## Pipeline 1: On-Chip SRAM (Entity Rendering)

### Boot-Time Setup

437 longwords (1,748 bytes) copied from SDRAM $0600254C to on-chip SRAM $C0000000 by a copy loop at $0600252C.

### Memory Layout

| Address | Size | Purpose |
|---------|------|---------|
| $C0000000-$C00006D3 | 1,748B | Rendering orchestrator code |
| $C0000700-$C000073F | 56B | Rendering context structure |
| $C0000740-$C0000773 | 52B | Edge buffer (entity data, preloaded per entity) |
| $C0000780+ | | Jump tables, additional data |

### Per-Entity Rendering Loop ($060024DC)

```
for each entity (R7 iterations):
    if *(R14+0) == 0: skip  (entity inactive)

    memcpy($C0000740, R13, 52)   // copy entity state to on-chip RAM
    R13 = *(R14+$10)              // load polygon data pointer
    R14 = $C0000700               // on-chip rendering context
    JSR $C0000000                 // execute on-chip renderer

    R13 += $30  (48-byte entity stride)
    R14 += $14  (20-byte entity descriptor stride)
```

### Entity Batches (Slave cmd $02 handler at $06000FA8)

| Batch | R13 (state) | R14 (desc) | Count | Inner R7 |
|-------|-------------|------------|-------|----------|
| 1 | $0600CA60 | $0600C128 | 4 | 4 |
| 2 | $0600CB20 | $0600C178 | 8 | 8 |
| 3 | $0600CD30 | $0600C254 | 8 outer | 3 inner |

R13 stride per outer iteration in batch 3: +$90. R14 stride: +$3C.
Total: up to 4 + 8 + 24 = 36 entity rendering passes per frame.

### On-Chip Code Characteristics

- **77 BSR calls**, ALL within the 1,748-byte block
- **1 JSR @R12** (indirect, likely via context pointer)
- **ZERO literal pool references** to SDRAM function addresses
- **Completely self-contained** — the SEGA engineers fit transform, cull, AND rasterize into 1.7KB of zero-wait-state on-chip SRAM

## Pipeline 2: SDRAM Cache (Display List Rendering)

### Entry Point

`main_coordinator_short` at $06003024, called via BSR from $06002FAE.
Reached through the Slave cmd $02 handler's setup chain.

### Dispatch Mechanism

BSRF R1 at $06003048: reads polygon type from display list, masks to even index 0-14, dispatches via computed offset table. Index 12 ($0C) = terminator.

### Complete Call Graph

```
main_coordinator_short ($06003024)
  │  BSRF R1 dispatch at $06003048
  │
  ├→ quad_batch_short ($060033A4)
  │   ├→ recursive_quad ($06003468) × 4 vertices per quad
  │   │   ├→ frustum_cull ($0600350A)  ← 12% HOTSPOT
  │   │   └→ recursive (self-call)
  │   └→ coord_transform ($06003368)   ← 17% HOTSPOT
  │       (also called from func_017 at $0600338A)
  │
  ├→ quad_batch_alt_short ($06003414)
  │   └→ coord_transform ($06003368)
  │
  └→ render_quad_short ($06003530) → span_filler_short ($0600358A)
      └→ edge_scan_short → pixel writes to SDRAM
```

### coord_transform Callers (4 sites)

| Caller | Address | Function |
|--------|---------|----------|
| func_017 | $0600338C | Quad helper (2B after func_016) |
| func_018 alt | $060033F4 | Quad batch alternate path |
| func_019 | $06003452 | Quad batch alt short |
| func_021 | $060034CA | Vertex transform |

### frustum_cull Callers (2 sites)

| Caller | Address | Function |
|--------|---------|----------|
| recursive_quad | $060034AE | func_020 alternate entry |
| vertex_transform | $060034D2 | func_021 area |

## cmd $23 Handler (Huffman Renderer Entry)

Master jump table cmd $23 → $06004AD0:

1. Read COMM4 longword (R9 = parameter from 68K)
2. Clear COMM6 (3-phase handshake ack)
3. R13 = $0600C000 (SDRAM context)
4. BSR $06004B00 (heavy subroutine, saves ALL 15 registers)
5. JSR $060043FC (exit handler)

The $06004B00 subroutine loads R10 = $06003000 and processes Huffman-compressed scene data.

## Key Data Structures

| Address | Stride | Count | Purpose |
|---------|--------|-------|---------|
| $0600C800 | $10 | 32 | Huffman data (active during racing) |
| $0600CA60 | $30 | 4 | Entity state batch 1 |
| $0600CB20 | $30 | 8 | Entity state batch 2 |
| $0600CD30 | $90 | 8 | Entity state batch 3 (outer stride) |
| $0600C128 | $14 | 4 | Entity descriptor batch 1 |
| $0600C178 | $14 | 8 | Entity descriptor batch 2 |
| $0600C254 | $3C | 8 | Entity descriptor batch 3 (outer stride) |
| $C0000700 | — | 1 | Rendering context (56 bytes) |
| $C0000740 | — | 1 | Edge buffer (52 bytes per entity) |

## Optimization Implications

### For coord_transform Batching (S-6)
The 4 call sites all load the same base X/Y values from the rendering context. Batching replaces 4 BSR → coord_transform with 1 BSR → batched version. This affects Pipeline 2 only.

### For Dual-SH2 Split (Phase 2)
- **Master takes:** coord_transform (17%) + frustum_cull (12%) from Pipeline 2
- **Slave keeps:** render_quad + span_filler + Pipeline 1 (on-chip)
- **Intercept point:** Before main_coordinator_short dispatch — Master pre-computes transformed/culled data, writes to SDRAM. Slave reads pre-computed results.
- **Pipeline 1 (on-chip) is untouchable** — self-contained, already optimal

### Hardware Architecture
- SH7604 cache: 4KB, configurable as 2KB cache + 2KB on-chip SRAM at $C0000000
- Each SH2 has its OWN independent cache — Master and Slave caches are separate
- On-chip SRAM data array: $C0000000-$C00007FF (direct write, zero wait state)
- Cache address array: $C0001000-$C00017FF (tag manipulation)
