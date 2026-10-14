# COMM Register Usage Analysis - Async Safety Validation

**Date:** 2026-01-27 (updated 2026-03-03)
**Purpose:** Document COMM register usage for command optimization safety
**Status:** Historical analysis — Phase 1A async approach **superseded** by B-003/B-004/B-005 single-shot protocols

---

## COMM Register Memory Map

### 68K Address Space

| Register | Address | SH2 Address | Size | Purpose |
|----------|---------|-------------|------|---------|
| **COMM0** | $00A15120 | $20004020 | word | Status/Control (command ready flag) |
| **COMM1** | $00A15122 | $20004022 | word | Command dispatch type |
| **COMM2** | $00A15124 | $20004024 | word | Work counter/status |
| **COMM3** | $00A15126 | $20004026 | word | Slave "OVRN" marker |
| **COMM4** | $00A15128 | $20004028 | long | **Parameter pointer (primary)** |
| **COMM5** | $00A1512A | $2000402A | word | Status flags |
| **COMM6** | $00A1512C | $2000402C | word | **Handshake/signal flag** |
| **COMM7** | $00A1512E | $2000402E | word | Command type extension |

---

## COMM Register Usage in Command Functions

### Function: sh2_send_cmd_wait ($00E316) — B-005 Single-Shot (Mar 2026)

> **Update (B-005):** The original 3-phase protocol (COMM4 write → COMM6 handshake → COMM4 write → COMM6 handshake) has been replaced with a single-shot protocol. `sh2_wait_response` ($E342) no longer exists.

**Current Assembly (B-005):**
```asm
sh2_send_cmd_wait:
.wait_ready:
    TST.B   COMM0_HI            ; Wait for Master SH2 idle
    BNE.S   .wait_ready
    ADDA.L  #$02000000,A0       ; Convert to SH2 SDRAM address
    MOVE.L  A0,COMM3            ; COMM3:4 = source pointer
    MOVE.L  A1,COMM5            ; COMM5:6 = dest pointer
    MOVE.B  #$25,COMM0_LO       ; Dispatch index
    MOVE.B  #$01,COMM0_HI       ; Trigger (written LAST)
.wait_consumed:
    TST.B   COMM0_LO            ; Wait for SH2 to read params
    BNE.S   .wait_consumed
    RTS
```

**COMM Registers Used:**
- **COMM0_HI** (read/write) - Polled for ready; written $01 as trigger
- **COMM0_LO** (write/read) - Dispatch index $25; polled for params-consumed handshake
- **COMM3:4** (write) - Source pointer A0 ($02xxxxxx SDRAM cache-through)
- **COMM5:6** (write) - Dest pointer A1 (full SH2 address, e.g. $0601xxxx)
- **COMM2_HI** - **NEVER WRITTEN** (Slave polls this for work commands)

**Blocking Behavior:**
- Wait COMM0_HI==0 (SH2 idle): ~20-50 cycles (scene init only, SH2 not busy)
- Wait COMM0_LO==0 (params consumed): ~30-60 cycles (SH2 reads immediately)
- Total: ~100 cycles per call (was ~350 with 3-phase)
- 8 calls during scene init only (not per-frame)

---

### Function: sh2_wait_response ($00E342) — **REMOVED (B-005)**

> **Removed in B-005 (Mar 2026).** The address slot $E342-$E358 is now NOP padding. The function previously polled COMM6 for the second phase of the 3-phase cmd $25 handshake. With B-005's single-shot protocol, all parameters are passed at once and no second handshake is needed.

---

## COMM Register Reuse Analysis

> **Update (B-003/B-004/B-005):** The original analysis below described the pre-optimization state where all 3 command functions used the same COMM4+COMM6 pattern. B-003/B-004/B-005 replaced these with dedicated COMM layouts per command type, making the reuse collision analysis historical. The "Phase 1A async" approach was **never implemented** — single-shot protocols achieved the same goal more simply.

### Current COMM Usage by Command (Post-Optimization)

| Command | Function | COMM Registers | Calls |
|---------|----------|---------------|-------|
| cmd $27 (B-003) | `sh2_cmd_27` | COMM2-6 (write), COMM7 (doorbell) | 21/frame |
| cmd $22 (B-004) | `sh2_send_cmd` | COMM0 (trigger+index), COMM2-6 (params) | 14/frame |
| cmd $25 (B-005) | `sh2_send_cmd_wait` | COMM0 (trigger+index), COMM3-6 (params) | 8/scene init |

Each command now uses the **params-consumed handshake** (COMM0_LO cleared by SH2 after reading) to prevent COMM overwrite. No COMM6 polling loops remain.

### Historical: Original Per-Frame COMM Slot Reuse (Pre-B-003/B-004/B-005)

The original code used a single pattern for all commands: COMM0 (poll) → COMM4 (param) → COMM6 (handshake), with a second COMM6 poll + COMM4 write phase for `sh2_send_cmd_wait`. All calls shared the same registers sequentially, relying on blocking to prevent corruption. This was safe but slow (~350 cycles per call for cmd $25, ~300 for cmd $22).

---

## Secondary Status Register: $FFFFC80E

### Discovery

Two call sites ($010B2C, $010BAE) immediately test a RAM address after `sh2_send_cmd_wait`:

**Call Site: $010B2C**
```asm
$010B2C: JSR     $E316(PC)       ; sh2_send_cmd_wait
$010B30: BTST    #4,$FFFFC80E    ; ← Test bit 4 of RAM variable
$010B38: BEQ     $10B40          ; Branch if clear
```

**Call Site: $010BAE**
```asm
$010BAE: JSR     $E316(PC)       ; sh2_send_cmd_wait
$010BB2: MOVEQ   #$00,D0         ; (2 instructions later)
$010BB4: MOVE.B  $FFFFFEA5,D0
$010BBA: BTST    #5,$FFFFC80E    ; ← Test bit 5 of RAM variable
$010BC2: BEQ     $10BAE          ; Loop back (polling!)
```

### Analysis

**Address:** $FFFFC80E
**Type:** 68K RAM (Work RAM, offset $C80E from $FF0000)
**Size:** Byte/Word
**Purpose:** Status flags for SH2 command completion

**Hypothesis:**
This is NOT a COMM hardware register (those are at $A15120-$A1512E). This is a **cached status byte** written by:
1. SH2 via shared memory writes, OR
2. 68K after reading COMM registers

**Polling Pattern:**
```asm
.wait_loop:
    BTST    #5,$FFFFC80E    ; Test bit 5
    BEQ     .wait_loop      ; Loop if clear (blocking!)
```

This is a **secondary blocking wait** in addition to the COMM register waits in `sh2_send_cmd_wait`.

**Implication for Async:**
These two call sites have **double blocking**:
1. `sh2_send_cmd_wait` blocks on COMM0/COMM6 (hardware)
2. Immediately followed by blocking on $FFFFC80E (RAM status)

**Phase 1A Decision:** EXCLUDE these 2 call sites from async optimization (keep them blocking).

---

## COMM Register Safety Summary

### Safe Patterns (15 of 17 call sites)

**Fire-and-Forget:**
```asm
JSR     sh2_send_cmd_wait       ; Submit command
LEA     $000ECC90,A0            ; Setup next command (no COMM reads)
MOVEA.L #$06019000,A1           ; Continue immediately
```

**Characteristics:**
- No COMM register reads after JSR
- No RAM status flag checks ($FFFFC80E)
- Setup for next command or continue with game logic
- Can be converted to async without behavioral changes

---

### Unsafe Patterns (2 of 17 call sites)

**Immediate Status Check:**
```asm
JSR     sh2_send_cmd_wait       ; Submit command
BTST    #4,$FFFFC80E            ; ← Immediate status check
BEQ     branch_target           ; ← Immediate conditional
```

**Characteristics:**
- Immediate read of $FFFFC80E RAM status byte
- Conditional branching based on SH2 completion
- **Cannot be async** without breaking synchronization logic
- Represent frame-boundary sync points

---

## Phase 1A Async Strategy — **SUPERSEDED**

> **Not implemented.** B-003/B-004/B-005 achieved the same savings via single-shot protocols instead of async queuing. The call site analysis below is preserved for reference.

### Original Target: 15 Safe Call Sites (of `sh2_send_cmd_wait`)

The 15 "safe" call sites and 2 "unsafe" call sites were identified correctly, but the optimization took a different path: converting the command protocol itself (single-shot) rather than making the call pattern async.

---

## Performance Impact — Actual Results (B-003/B-004/B-005)

### Before (Original Blocking Model)

```
sh2_cmd_27:        21 calls/frame × ~250 cycles = ~5,250 cycles (2 blocking loops)
sh2_send_cmd:      14 calls/frame × ~300 cycles = ~4,200 cycles (3 blocking loops)
sh2_send_cmd_wait:  8 calls/init  × ~350 cycles = ~2,800 cycles (3-phase, scene init only)
────────────────────────────────────────────────────────────────────────────
Total per-frame:                                   ~9,450 cycles (~7.4% of 68K budget)
Total per-init:                                    ~2,800 cycles additional
```

### After (B-003 + B-004 + B-005)

```
sh2_cmd_27 (B-003):  21 calls/frame × ~50 cycles  = ~1,050 cycles (fire-and-forget)
sh2_send_cmd (B-004): 14 calls/frame × ~170 cycles = ~2,380 cycles (single-shot)
sh2_send_cmd_wait (B-005): 8 calls/init × ~100 cycles = ~800 cycles (single-shot)
────────────────────────────────────────────────────────────────────────────
Total per-frame:                                      ~3,430 cycles (~2.7% of 68K budget)
Total per-init:                                       ~800 cycles additional
Savings per frame:                                    ~6,020 cycles (64%)
```

**FPS impact:** ~0% measurable. The 68K is saturated on non-command work (game logic, rendering). Reducing command overhead from 7.4% to 2.7% frees ~6,000 cycles but these are absorbed by existing bottlenecks. Scene transitions are ~2,000 cycles faster.

---

## Validation Status

### Analysis (Complete)

- [x] **COMM register usage documented** (COMM0, COMM4, COMM6 for all original calls)
- [x] **COMM reuse collision identified** (all calls shared same registers)
- [x] **Unsafe call sites identified** (2 sites with $FFFFC80E RAM status checks)
- [x] **Safe call sites enumerated** (15 sites)

### Implementation (B-003/B-004/B-005 — Complete)

- [x] **B-003:** `sh2_cmd_27` → fire-and-forget via COMM7 doorbell (Feb 2026)
- [x] **B-004:** `sh2_send_cmd` → single-shot via COMM0+COMM2-6 (Feb 2026)
- [x] **B-005:** `sh2_send_cmd_wait` → single-shot via COMM0+COMM3-6 (Mar 2026)
- [x] **`sh2_wait_response` removed** — address slot overwritten by B-005 NOP padding
- [x] **3600-frame autoplay test passed** (menus + race, no crash)

---

## Related Documents

- [ASYNC_PHASE1A_SAFETY_CHECKLIST.md](ASYNC_PHASE1A_SAFETY_CHECKLIST.md) - Historical: Phase 1A async safety checks (not implemented)
- [ASYNC_COMMAND_IMPLEMENTATION_PLAN.md](ASYNC_COMMAND_IMPLEMENTATION_PLAN.md) - Historical: Full async implementation plan (superseded by single-shot)
- [68K_BOTTLENECK_ANALYSIS.md](../profiling/68K_BOTTLENECK_ANALYSIS.md) - Bottleneck identification
- [68K_SH2_COMMUNICATION.md](../68K_SH2_COMMUNICATION.md) - Current protocol reference (B-003/B-004/B-005 sections)

---

**Status:** ✅ Analysis complete. Optimization delivered via B-003/B-004/B-005 (single-shot protocols, not async queuing).
**Result:** Per-frame command overhead reduced from ~9,450 to ~3,430 cycles (64% reduction). No FPS gain (68K saturated on non-command work).
