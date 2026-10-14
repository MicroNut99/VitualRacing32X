# Slave SH2 Dispatch Architecture

**Created:** 2026-03-16
**Purpose:** Document the dual-SH2 dispatch system — how Master and Slave coordinate, Slave command routing, rendering pipeline sequencing, and optimization opportunities (S-5/S-8/S-9).

---

## 1. Dual Dispatch Overview

The Master and Slave SH2 CPUs have **completely independent** dispatch loops polling different COMM registers:

| CPU | Dispatch Loop | SDRAM Addr | Polls | Jump Table | Entries |
|-----|--------------|-----------|-------|-----------|---------|
| **Master** | $020460 | $06000460 | COMM0_HI ($20004020) | $06000780 | 16 (cmd $00-$0F) |
| **Slave** | $020592 | $06000592 | COMM2_HI ($20004024) | $060005C8 | 8+ |

**There is no direct cross-trigger.** The 68K independently submits commands to Master (via COMM0) and Slave (via COMM2). They operate in parallel.

---

## 2. Master Dispatch Loop ($06000460)

```
Poll: MOV.B @R8,R0        ; R8=$20004020, read COMM0_HI
      CMP/EQ #0,R0        ; idle?
      BT Poll              ; yes → keep polling
      MOV.B @(1,R8),R0     ; read COMM0_LO = command index
      SHLL2 R0             ; ×4 for table offset
      MOV.L @(table,R0),R0 ; load handler address from $06000780
      JSR @R0              ; dispatch
      BRA Poll             ; loop
```

**Master command handlers** (jump table at $06000780):

| COMM0_LO | Handler | Purpose |
|----------|---------|---------|
| $00 | $06000490 | Idle/no-op (ACK only) |
| $01 | $060008A0 | Scene init orchestrator (10 subroutines) |
| $02 | $06000CFC | Scene orchestrator (entity loop callers) |
| $03 | $06000CC4 | Racing per-frame trigger (buffer clear + done) |
| $04 | $060012CC | Full scene rendering (32 entities) |
| $05 | $06001924 | Racing per-frame render (22 entities + visibility cull) |
| $06 | $06001A0C | Bulk DMA copy (track data, 56KB) |
| $07-$0F | $06000490 | Unused → default idle |

**Completion:** Handlers call `$060043FC` (clear COMM0_HI, set COMM1_LO bit 0) or `$060043F0` (FM check + completion).

---

## 3. Slave Dispatch Loop ($06000592)

```
Poll: MOV.L @(48,PC),R1   ; R1=$20004024 (COMM2 address)
      MOV.B @R1,R0         ; read COMM2_HI = command byte
      CMP/EQ #0,R0         ; idle?
      BT Idle              ; yes → $020608 (COMM7 doorbell check)
      MOV R0,R2            ; R2 = command ID
      MOVA @(40,PC),R0     ; R0 = jump table base ($060005C8)
      SHLL2 R2             ; R2 = command × 4
      MOV.L @(R0,R2),R0    ; load handler address
      JSR @R0              ; dispatch
      BRA Poll             ; loop
```

**Slave command handlers** (jump table at $060005C8):

| COMM2 | Handler | Purpose |
|-------|---------|---------|
| $00 | $06000608 | Idle → COMM7 doorbell check |
| $01 | $060039F0 | Scene/palette handler |
| $02 | $06000FA8 | **Entity rendering entry point** (primary render dispatch) |
| $03 | $06001384 | Rendering handler 3 |
| $04 | $06000D88 | Rendering handler 4 |
| $05 | $06001380 | Rendering handler 5 |
| $06 | $0600135C | Rendering handler 6 |
| $07 | $06000DA8 | Rendering handler 7 |

**Idle loop** at $06000608: When COMM2_HI = 0, the Slave checks COMM7 for the async doorbell ($0027 = cmd_27 pixel work). If COMM7 is non-zero, it reads pixel parameters from COMM2-6, processes them inline, clears COMM7, and loops.

---

## 4. COMM Register Namespace

| Register | Owner | Purpose | Direction |
|----------|-------|---------|-----------|
| COMM0_HI | Master SH2 | Command trigger (non-zero = busy) | 68K → Master |
| COMM0_LO | Master SH2 | Command index | 68K → Master |
| COMM1_HI | — | Track selection flag (race init) | 68K → SH2 |
| COMM1_LO | Master SH2 | Bit 0 = "done" signal | Master → 68K |
| COMM2_HI | Slave SH2 | Command trigger (non-zero = dispatch) | 68K → Slave |
| COMM2_LO-COMM6 | Both | Parameter passing (B-003, B-004) | 68K → SH2 |
| COMM7 | Slave SH2 | Async doorbell ($0027 = cmd_27 drain) | 68K → Slave |

**Hazard:** COMM2 is dual-purpose — Slave polls COMM2_HI for dispatch, but B-004 cmd_22 also uses COMM2-6 for block-copy parameters sent to the Master. These don't conflict because cmd_22 writes happen AFTER the Master confirms idle (COMM0_HI=0), and the Slave's COMM2 dispatch is independent.

---

## 5. Rendering Pipeline Sequencing

**Both rendering pipelines run on the Slave SH2 only.**

### Pipeline 1: On-Chip SRAM ($C0000000)

- **Code size:** 1,748 bytes copied from SDRAM $0600254C at boot
- **Self-contained:** 77 internal BSR calls, ZERO external SDRAM references
- **Entry point:** `$060024DC` (entity_loop), called by Master handlers $01 and $05
- **Batch processing:** 36 entities/frame in 3 batches (4 + 8 + 24)
- **Per-entity flow:** Load entity state (52B) to SRAM $C0000740, JSR `$C0000000`, loop
- **Performance:** Zero wait states, zero cache misses — **untouchable**

### Pipeline 2: SDRAM Cache

- **Entry point:** `$06003024` (main_coordinator_short)
- **Dispatch:** BSRF R1 at $06003048 — reads polygon type from display list, masks to index 0-14
- **Call graph:**
  ```
  main_coordinator_short ($06003024)
    → quad_batch_short (×4)
        → coord_transform ($06003368) — 12% hotspot (was 17%, S-6 saved 5%)
        → recursive_quad → frustum_cull ($0600350A) — 12% hotspot
    → render_quad_short
        → span_filler_short ($0600358A) — 8% hotspot
  ```
- **Sequencing:** Runs AFTER Pipeline 1 in the same frame

### How They're Triggered

During racing, the per-frame cycle is:
1. 68K writes COMM0 ($01/$02) → Master dispatches
2. Master handler calls entity loop `$060024DC` (Pipeline 1 on Slave via SRAM)
3. Master handler calls main_coordinator `$06003024` (Pipeline 2 on Slave via SDRAM)
4. Master handler signals completion via COMM1_LO bit 0

**Key insight:** "Master handler" here means the code dispatched by the Master's poll loop, but the actual rendering (both pipelines) executes on the **Slave SH2's instruction pipeline**. The Master and Slave share the same SDRAM address space — when the Master "calls" `$060024DC`, it's the Slave that fetches and executes that code.

**Correction:** Based on profiling, the Master is 0-36% utilized while the Slave is 78%. The Master's handlers ARE dispatched by the Master's poll loop, but the rendering call chain runs on whichever CPU's dispatch loop invoked it. Handler $04/$05 (rendering) run on the **Master** CPU according to the jump table at $06000780, but they call into code that may delegate to Slave via shared SDRAM.

---

## 6. Optimization Opportunities

### S-5: Behind-Camera Culling

Handler $05 (`$06001924`) has built-in visibility culling:
- Reads `$0600C0C8` / `$0600C0CA` (camera view range words)
- If either is `$FFFF` or both are equal → skips heavy render path (steps 6-11)
- **Intervention:** 68K writes culling data to `$0600C0C8`/`$0600C0CA` based on camera position

### S-8: Master as Vertex Transform Coprocessor

Master is 0-36% utilized. Could offload from Slave's SDRAM pipeline:
- `coord_transform` (~12% of Slave) — pack X/Y coordinates
- `frustum_cull` (~12% of Slave) — per-polygon visibility

**Requirements:**
1. New Master command that pre-computes vertex transforms
2. Output to SDRAM buffers that Slave reads instead of computing
3. Explicit handoff mechanism (e.g., flag in shared SDRAM)
4. Must handle entity N+1 while Slave rasterizes entity N (pipeline overlap)

### S-9: Frustum Pre-Culling on 68K

Entity data at `$0600C800` (32 entries × 16B, byte flags at offset +0):
- 68K computes coarse per-entity frustum test
- Writes flag=0 to skip entities behind camera
- Handler $04 reads these flags — entities with flag=0 skipped in entity loop

---

## 7. Key Files

| File | Purpose |
|------|---------|
| `disasm/sections/code_20200.asm` (lines 315-585) | Master + Slave dispatch loops |
| `disasm/sh2/3d_engine/slave_command_dispatcher.asm` | Slave dispatch with comments |
| `analysis/sh2-analysis/SH2_COMMAND_HANDLER_REFERENCE.md` | All 7 Master handlers |
| `analysis/sh2-analysis/SH2_RENDERING_ARCHITECTURE.md` | Pipeline 1+2 architecture |
| `analysis/sh2-analysis/SH2_3D_ENGINE_DEEP_DIVE.md` | Algorithm details |
| `analysis/architecture/MASTER_SH2_DISPATCH_ANALYSIS.md` | Master dispatch + B-006 |
| `analysis/68K_SH2_COMMUNICATION.md` | COMM protocol |
