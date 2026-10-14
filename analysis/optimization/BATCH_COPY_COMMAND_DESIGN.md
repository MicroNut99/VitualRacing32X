# Batch Copy Command Design (Option A2)

**Date:** 2026-01-29
**Status:** OBSOLETE (2026-03-03)
**Target:** Reduce 68K blocking waits in 8-call sequence ($00FF12-$00FF9E)

> **OBSOLETE:** This design is invalidated by three findings:
> 1. **SH2 cannot access Work RAM.** The proposed batch table at $FFF000 (SH2 $0220F000) is unmapped space. Proven broken in B-003 v1-v3.
> 2. **B-003/B-004/B-005 already captured most savings.** Per-frame command overhead is ~4,000 cycles (3.1% of 68K), down from ~12,000+. The "+10-20% FPS" estimate is obsolete.
> 3. **The 8-call target (`sh2_send_cmd_wait`) only runs during scene init**, not per frame. B-005 converted it to single-shot protocol instead.
>
> The $300500 expansion ROM slot is now used by `cmd25_single_shot` (B-005).

---

## Problem Statement

The 8-call sequence at $00FF12-$00FF9E issues 8 consecutive calls to `sh2_send_cmd_wait`:

| Call | Source | Destination | Type |
|------|--------|-------------|------|
| 1 | $000F3D80 | $06014000 | Fixed |
| 2 | $000ECC90 | $06019000 | Fixed |
| 3 | lookup[$FEB1] | $06019700 | Variable |
| 4 | lookup[$FEA5] | $06019C80 | Variable |
| 5 | $000F4620 | $0601A200 | Fixed |
| 6 | $000EBB40 | $06020000 | Fixed |
| 7 | $000EB980 | $06023200 | Fixed |
| 8 | $000F4E40 | $06024000 | Fixed |

Each call to `sh2_send_cmd_wait` ($E316) involves:
1. Wait for COMM0 == 0 (SH2 ready)
2. Send source address via COMM4
3. Write COMM6 = $0101 (handshake signal)
4. Issue command $25
5. **Wait for COMM6 == 0** (SH2 latched source)
6. Send dest address via COMM4
7. Write COMM6 = $0101
8. Return (no second wait!)

**Critical Insight:** The COMM6 wait at step 5 **cannot be skipped** - it ensures the SH2 has latched the source address before the 68K overwrites COMM4 with the destination.

**Total blocking overhead:** 8 handshakes × ~200-400 cycles = **1,600-3,200 cycles/call**

---

## Proposed Solution: SH2-Side Batch Command

Instead of 8 separate handshakes, build a batch table and issue a single command.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        68K Side                             │
├─────────────────────────────────────────────────────────────┤
│ 1. Build batch table in Work RAM ($FFF000)                  │
│    [count=8][src0][dst0][src1][dst1]...[src7][dst7]         │
│                                                             │
│ 2. Convert table address: $FFF000 + $02000000 = $0220F000   │
│                                                             │
│ 3. Issue single command:                                    │
│    COMM4 = $0220F000 (table address)                        │
│    COMM1 = $26 (BATCH_COPY command)                         │
│    COMM0 = $01 (trigger)                                    │
│                                                             │
│ 4. Single wait for COMM6 == 0 (all copies complete)         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                       SH2 Side                              │
├─────────────────────────────────────────────────────────────┤
│ batch_copy_handler:                                         │
│   1. Read table address from COMM4                          │
│   2. Read count from table[0]                               │
│   3. For i = 0 to count-1:                                  │
│      a. Read src[i] from table[2 + i*8]                     │
│      b. Read dst[i] from table[6 + i*8]                     │
│      c. Call internal copy routine (reuse cmd $25 logic)    │
│   4. Clear COMM6 (signal complete to 68K)                   │
│   5. Clear COMM0 (ready for next command)                   │
│   6. Return                                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Command Protocol

### New Command: $26 (BATCH_COPY)

| Register | Value | Purpose |
|----------|-------|---------|
| COMM0 | $01 | Trigger |
| COMM1 | $26 | Command ID |
| COMM4-5 | table_addr | Pointer to batch table (SH2 address) |
| COMM6 | $0101 | Handshake (cleared by SH2 when done) |

### Batch Table Format (in 68K Work RAM)

```
Offset  Size   Content
------  ----   -------
$00     2      count (number of entries, 1-16)
$02     4      src[0] (SH2 address)
$06     4      dst[0] (SH2 address)
$0A     4      src[1]
$0E     4      dst[1]
...
$02+n*8 4      src[n-1]
$06+n*8 4      dst[n-1]
```

**Table Size:** 2 + (count × 8) bytes
**Maximum entries:** 16 (128 bytes + 2 = 130 bytes)

### Address Conversion

68K addresses must be converted to SH2 address space:

| 68K Range | SH2 Range | Conversion |
|-----------|-----------|------------|
| $000000-$3FFFFF | $02000000-$023FFFFF | ROM: +$02000000 |
| $FF0000-$FFFFFF | $0220F000-$0220FFFF | Work RAM: +$02000000 |
| $06000000-$0603FFFF | Same | SDRAM: No change |

---

## Implementation Details

### 1. Jump Table Entry

Add entry at $06000780 + ($26 × 4) = $06000798:

```asm
; In jump table initialization (68K side, during boot)
; At offset $98 from table base:
    dc.l    $02300300       ; Handler address in expansion ROM
```

### 2. SH2 Handler (Expansion ROM at $300300)

```asm
; batch_copy_handler at $300300
; Input: COMM4 = table address (SH2 space)
; Clobbers: R0-R5

batch_copy_handler:
    mov.l   comm_base,r8        ; R8 = $20004020
    mov.l   @(8,r8),r4          ; R4 = table address from COMM4

    ; Read count
    mov.w   @r4,r5              ; R5 = count (16-bit)
    add     #2,r4               ; R4 points to first entry

    ; Check for zero count
    tst     r5
    bt      .done

.copy_loop:
    ; Read src address
    mov.l   @r4+,r1             ; R1 = src, R4 += 4

    ; Read dst address
    mov.l   @r4+,r2             ; R2 = dst, R4 += 4

    ; Call internal copy routine
    ; (This calls the existing cmd $25 implementation)
    mov     r1,r6               ; R6 = src (for copy routine)
    mov     r2,r7               ; R7 = dst
    bsr     internal_copy       ; Reuse existing copy logic

    ; Decrement and loop
    dt      r5                  ; R5--, set T if R5 == 0
    bf      .copy_loop          ; Loop if R5 != 0

.done:
    ; Signal completion
    mov     #0,r0
    mov.w   r0,@(12,r8)         ; COMM6 = 0 (done)
    mov.b   r0,@r8              ; COMM0 = 0 (ready)
    rts
    nop

comm_base:
    .long   $20004020
```

**Size estimate:** ~60-80 bytes

### 3. Internal Copy Routine

The existing command $25 handler performs the actual copy. We need to either:

**Option A:** Call it directly (requires understanding its calling convention)
**Option B:** Inline a simple memcpy loop

For simplicity, I recommend **Option B** - a small memcpy loop:

```asm
; internal_copy: Copy fixed-size block
; Input: R6 = src, R7 = dst
; Copy size: TBD (need to determine from cmd $25 analysis)

internal_copy:
    mov.l   copy_size,r0        ; R0 = bytes to copy (e.g., 0x500)
    shlr2   r0                  ; R0 = longwords to copy

.copy_word:
    mov.l   @r6+,r1             ; Read from src
    mov.l   r1,@r7              ; Write to dst
    add     #4,r7
    dt      r0
    bf      .copy_word
    rts
    nop

copy_size:
    .long   $00000500           ; 1280 bytes (adjust based on analysis)
```

### 3. SH2 Handler with Explicit Sizes (Recommended)

```asm
; batch_copy_handler at $300300
; Input: COMM4 = table address (SH2 space)
; Table format: [count:16][src:32][dst:32][size:32]...

batch_copy_handler:
    mov.l   comm_base,r8        ; R8 = $20004020
    mov.l   @(8,r8),r4          ; R4 = table address from COMM4

    ; Read count
    mov.w   @r4,r5              ; R5 = count (16-bit)
    extu.w  r5,r5               ; Zero-extend
    add     #2,r4               ; R4 points to first entry

    tst     r5
    bt      .done

.copy_loop:
    mov.l   @r4+,r1             ; R1 = src
    mov.l   @r4+,r2             ; R2 = dst
    mov.l   @r4+,r3             ; R3 = size (bytes)
    shlr2   r3                  ; R3 = size/4 (longwords)

    tst     r3
    bt      .next_entry

.inner_copy:
    mov.l   @r1+,r0             ; Read longword from src
    mov.l   r0,@r2              ; Write to dst
    add     #4,r2
    dt      r3                  ; R3--, set T if zero
    bf      .inner_copy

.next_entry:
    dt      r5                  ; count--
    bf      .copy_loop

.done:
    mov     #0,r0
    mov.w   r0,@(12,r8)         ; COMM6 = 0 (done)
    mov.b   r0,@r8              ; COMM0 = 0 (ready)
    rts
    nop

.align 4
comm_base:
    .long   $20004020
```

**Size:** ~50 bytes
**Cycles per longword:** ~8 (mov.l read, mov.l write, add, dt, bf)

---

## Determining Copy Size

Command $25 transfers data but the size isn't explicitly passed. Possibilities:

1. **Fixed size** - All cmd $25 copies are the same size
2. **Header-encoded** - Size is in a header at the source address
3. **Destination-determined** - Size depends on destination region

### Investigation Steps

1. Profile the 8-call sequence destinations:
   - $06014000: Size = ?
   - $06019000: Size = ?
   - etc.

2. Compare source data structures for size fields

3. Disassemble the SH2 command $25 handler to see how it determines size

**Recommendation:** Use explicit sizes in the table:

```
Offset  Size   Content
------  ----   -------
$00     2      count
$02     4      src[0]
$06     4      dst[0]
$0A     4      size[0]    ; Explicit size per entry (bytes)
$0E     4      src[1]
$12     4      dst[1]
$16     4      size[1]
...
```

**Entry size:** 12 bytes (src + dst + size)
**Table size:** 2 + (count × 12) bytes
**Max entries:** 10 (122 bytes)

This is safer than relying on implicit sizes and provides more flexibility.

---

## 68K Patching

### Original Code ($00FF06-$00FF9E)

```asm
; 8 consecutive sh2_send_cmd_wait calls
LEA     $000F3D80,A0
MOVEA.L #$06014000,A1
JSR     loc_00E316(PC)      ; Call 1

LEA     $000ECC90,A0
MOVEA.L #$06019000,A1
JSR     loc_00E316(PC)      ; Call 2

; ... 6 more calls ...
```

### Patched Code

```asm
; Build batch table at $FFF000
LEA     $FFF000,A2          ; A2 = table pointer
MOVE.W  #8,(A2)+            ; count = 8

; Entry 1: Fixed
MOVE.L  #$02000000+$000F3D80,(A2)+  ; src (converted)
MOVE.L  #$06014000,(A2)+            ; dst

; Entry 2: Fixed
MOVE.L  #$02000000+$000ECC90,(A2)+
MOVE.L  #$06019000,(A2)+

; Entry 3: Variable (need to compute)
MOVEQ   #0,D0
MOVE.B  $FEB1.W,D0
ADD.L   D0,D0
ADD.L   D0,D0
LEA     $00890084,A0
MOVEA.L (A0,D0.W),A0
ADDA.L  #$02000000,A0
MOVE.L  A0,(A2)+            ; src (computed + converted)
MOVE.L  #$06019700,(A2)+    ; dst

; Entry 4: Variable
MOVEQ   #0,D0
MOVE.B  $FEA5.W,D0
ADD.L   D0,D0
ADD.L   D0,D0
LEA     $00890090,A0
MOVEA.L (A0,D0.W),A0
ADDA.L  #$02000000,A0
MOVE.L  A0,(A2)+
MOVE.L  #$06019C80,(A2)+

; Entries 5-8: Fixed
MOVE.L  #$02000000+$000F4620,(A2)+
MOVE.L  #$0601A200,(A2)+
MOVE.L  #$02000000+$000EBB40,(A2)+
MOVE.L  #$06020000,(A2)+
MOVE.L  #$02000000+$000EB980,(A2)+
MOVE.L  #$06023200,(A2)+
MOVE.L  #$02000000+$000F4E40,(A2)+
MOVE.L  #$06024000,(A2)+

; Issue batch command
JSR     sh2_batch_copy      ; New function
```

### New 68K Function: sh2_batch_copy

```asm
sh2_batch_copy:
    ; Wait for SH2 ready
.wait_ready:
    TST.B   $00A15120
    BNE.S   .wait_ready

    ; Send table address (converted to SH2 space)
    MOVE.L  #$0220F000,$00A15128    ; COMM4 = table addr ($FFF000 + $02000000)

    ; Set handshake
    MOVE.W  #$0101,$00A1512C        ; COMM6 = busy

    ; Issue command
    MOVE.B  #$26,$00A15121          ; COMM1 = BATCH_COPY
    MOVE.B  #$01,$00A15120          ; COMM0 = trigger

    ; Wait for completion
.wait_done:
    TST.B   $00A1512C
    BNE.S   .wait_done

    RTS
```

---

## Expected Performance

### Before (8 separate calls)

| Metric | Value |
|--------|-------|
| COMM0 waits | 8 |
| COMM6 waits | 8 |
| Total blocking | 16 wait loops |
| Estimated cycles | 1,600-3,200 |

### After (1 batch call)

| Metric | Value |
|--------|-------|
| COMM0 waits | 1 |
| COMM6 waits | 1 |
| Total blocking | 2 wait loops |
| Estimated cycles | 200-400 |

**Savings:** ~1,400-2,800 cycles per batch = **75-87.5% reduction**

### Frame-Level Impact

If this sequence runs once per frame:
- Before: ~2,400 cycles (average)
- After: ~300 cycles (average)
- **Saved: ~2,100 cycles/frame**

With 68K at 127,987 cycles/frame:
- **Improvement: ~1.6% of 68K budget freed**

---

## Implementation Phases

### Phase 1: Proof of Concept (SH2 handler only)
1. Implement minimal batch_copy_handler in expansion ROM
2. Hardcode copy size (determine from analysis)
3. Test with single-entry batch

### Phase 2: 68K Integration
1. Implement sh2_batch_copy function
2. Add jump table entry for cmd $26
3. Test with 8-entry batch (this sequence)

### Phase 3: Full Rollout
1. Patch the $00FF12-$00FF9E sequence
2. Profile before/after
3. Apply to other batch sequences ($00F2A6-$00F316, $00E774-$00E7A4)

---

## Open Questions

1. **Copy size:** What size does cmd $25 use? Need to:
   - Disassemble SH2 cmd $25 handler
   - Or measure the destination regions

2. **Table location:** $FFF000 is safe? Check for conflicts with:
   - Stack
   - Other game data
   - Sound driver

3. **Variable entries:** The lookup tables at $890084 and $890090 - are these always valid?

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Wrong copy size | Medium | Disassemble cmd $25 handler |
| Table address conflict | Low | Choose unused work RAM region |
| Timing issues | Low | SH2 handler is synchronous |
| Original code regression | Low | Keep fallback path |

---

## Next Steps

1. [ ] Disassemble SH2 cmd $25 handler to determine copy size
2. [ ] Choose safe table location in work RAM
3. [ ] Implement SH2 batch_copy_handler in expansion ROM
4. [ ] Test with single entry
5. [ ] Implement 68K sh2_batch_copy function
6. [ ] Patch the 8-call sequence
7. [ ] Profile and measure improvement

---

## Recommended Implementation Path

### Minimal Viable Prototype

1. **Determine copy sizes empirically:**
   - Add debug output to count bytes copied per cmd $25 call
   - Or: Calculate from destination region sizes

2. **Hardcode sizes initially:**
   | Entry | Destination | Likely Size |
   |-------|-------------|-------------|
   | 1 | $06014000 | $5000 (20KB)? |
   | 2 | $06019000 | $700 (1.75KB)? |
   | 3 | $06019700 | $580 (1.4KB)? |
   | 4 | $06019C80 | $580? |
   | 5 | $0601A200 | $5E00? |
   | 6 | $06020000 | $3200? |
   | 7 | $06023200 | $E00? |
   | 8 | $06024000 | TBD |

3. **Build minimal SH2 handler** (~50 bytes)

4. **Test single-entry batch** before 8-entry

### Alternative: Simpler Batch (No Sizes)

If determining sizes proves difficult, fall back to:
- Batch table contains only {src, dst} pairs
- SH2 handler calls the existing cmd $25 logic internally
- Still reduces handshakes from 8 to 1 (wait-for-all-done pattern)

This requires understanding cmd $25's internal interface but avoids size guesswork.

---

**Document:** BATCH_COPY_COMMAND_DESIGN.md
**Created:** 2026-01-29
**Purpose:** Design document for SH2-side batch copy optimization

