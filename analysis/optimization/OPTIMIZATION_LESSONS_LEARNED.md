# Optimization Attempt: Lessons Learned

**Date**: January 6, 2026
**Last Updated**: January 24, 2026
**Attempted**: coord_transform Inline Optimization
**Result**: ✅ SUCCESS (vertex_transform) / ❌ Complex (quad_helper-019)
**Lesson**: Expansion ROM approach works for standalone functions
**Status**: Proof of concept validated for vertex_transform; quad_helper-019 require different approach

---

## ✅ SUCCESSFUL OPTIMIZATION: vertex_transform (January 24, 2026)

### Summary

**vertex_transform** (Coordinate Transform + Cull loop) was successfully optimized by:
1. Relocating the function to expansion ROM at `$0230003C`
2. Inlining coord_transform (coordinate transform) to eliminate BSR/RTS overhead
3. Using a trampoline at the original location to redirect calls

**Result**: Working ROM with coord_transform inlined at one call site

### Implementation Details

| Component | Location | Size |
|-----------|----------|------|
| Trampoline | `$020234C8` (original vertex_transform) | 12 bytes |
| Optimized function | `$0230003C` (expansion ROM) | 96 bytes |
| Inlined coord_transform | First 32 bytes of optimized | 32 bytes |

**Cycle savings**: ~6 cycles/call × 800 polygons = **4,800 cycles/frame**

### Why vertex_transform Worked (Unlike quad_helper-019)

1. **Standalone function**: No cross-function branching or shared code paths
2. **Clean entry/exit**: Standard prologue/epilogue pattern
3. **Predictable behavior**: Simple loop with nested function call

### Trampoline Pattern

```assembly
; Original vertex_transform location ($020234C8) - now a trampoline
    MOV.L   @(1,PC),R0      ; $D001 - Load expansion address
    JMP     @R0             ; $402B - Jump to expansion ROM
    NOP                     ; $0009 - Delay slot
    NOP                     ; $0009 - Padding
    .long   $0230003C       ; Target address in expansion ROM
```

**Overhead**: ~4-6 cycles for trampoline, but saves 6 cycles from inlined BSR/RTS = **net positive**

### Critical Technical Lessons

#### 1. 4-Byte Alignment for Literal Pools

**Problem**: SH2 `MOV.L @(disp,PC),Rn` requires the literal address to be 4-byte aligned.

**Symptom**: `invalid PC, aborting: 00090009` - jumped to NOP padding

**Solution**: Place optimized functions at 4-byte aligned addresses (e.g., `$30003C` not `$300042`)

**Formula for EA**: `EA = (PC & ~3) + 4 + disp×4`

#### 2. SH2 Address Space Mapping

**Problem**: Confused `$0222350A` with `$0202350A` (extra '2' digit)

| Address | File Offset | Valid? |
|---------|-------------|--------|
| `$0202350A` | `$2350A` | ✅ Code |
| `$0222350A` | `$22350A` | ❌ Data/garbage |

**Lesson**: Double-check all literal addresses. SH2 ROM maps at `$02000000`, so `$02XXYYZZ` → file offset `$XXYYZZ`.

#### 3. Instruction Encoding Verification

**Problem**: Original code comment said `MOV.B R0,@(1,R5)` but actual instruction was `MOV.W @(2,R8),R0`

| Opcode | Instruction | Operation |
|--------|-------------|-----------|
| `$8051` | `MOV.B R0,@(1,R5)` | **STORE** byte |
| `$8581` | `MOV.W @(2,R8),R0` | **LOAD** word |

**Symptom**: Glitchy 3D rendering (wrong data being written/read)

**Lesson**: Always verify instruction encoding against disassembly, not just comments.

#### 4. MOV.W Displacement Encoding

**Problem**: `mov.w @(1,r8),r0` caused assembly error ("misaligned offset")

**Reason**: MOV.W uses word-scaled displacement. `d=1` in encoding means byte offset 2.

**Solution**: Write `mov.w @(2,r8),r0` in assembly to get `d=1` encoding (matches original `$8581`)

### Files Modified

| File | Purpose |
|------|---------|
| `disasm/sh2/expansion/vertex_transform_optimized.asm` | Optimized SH2 source |
| `disasm/sh2/generated/vertex_transform_optimized.inc` | Generated dc.w opcodes |
| `disasm/sections/expansion_300000.asm` | Expansion ROM section |
| `disasm/sections/code_22200.asm` | Trampoline at original location |

### Build Process

```bash
# 1. Regenerate include file after editing source
./tools/asm_to_dcw.sh disasm/sh2/expansion/vertex_transform_optimized.asm \
    disasm/sh2/generated/vertex_transform_optimized.inc

# 2. Rebuild ROM
make all

# 3. Test
picodrive build/vr_rebuild.32x
```

---

## Historical Context: The Failed Approaches

The following section documents the **original failed attempts** before the expansion ROM approach was validated.

---

## What Happened

### The Crash

**Test ROM**: `Virtua Racing - Test1.32x`
**Status**: Does not boot (file not present in repo as of 2026-01-24)
**Cause**: Code expansion overwrote critical loop control logic

### Root Cause Analysis

**Original code at 0x02338C** (4 bytes):
```assembly
BF EC    BSR $02223368    ; Call coord_transform
00 09    NOP              ; Delay slot
```

**Attempted replacement** (32 bytes):
```assembly
; Inline coord_transform body (32 bytes)
51 E7    MOV.L @($1C,R14),R1
52 E8    MOV.L @($20,R14),R2
... (15 instructions total)
1E 4D    MOV.L R4,@($34,R14)
```

**Code we destroyed** (bytes 4-31):
```assembly
60 A2    MOV.L @R10,R0        ; ← DESTROYED: Load value
88 00    CMP/EQ #0,R0         ; ← DESTROYED: Check if zero
8B 06    BF $022233A4         ; ← DESTROYED: Conditional branch
7A FC    ADD #-4,R10          ; ← DESTROYED: Pointer adjustment
47 10    DT R7                ; ← DESTROYED: Loop counter decrement
8F F9    BF/S $02223390       ; ← DESTROYED: Loop branch
7B C0    ADD #-64,R11         ; ← DESTROYED: (delay slot)
4F 26    LDS.L @R15+,PR       ; ← DESTROYED: Restore return address
00 0B    RTS                  ; ← DESTROYED: Return
00 09    NOP                  ; ← DESTROYED: Delay slot
```

**Impact**: We destroyed a **critical polygon processing loop** that:
- Iterates over polygon array
- Checks for zero/null entries
- Updates loop counters
- Returns to caller

**Result**: CPU executes our inlined code correctly, then continues into garbage bytes, causing undefined behavior → crash.

---

## Why This Is Hard

### The Code Expansion Problem

**Challenge**: Inlining replaces 4 bytes with 32 bytes (8× expansion)

**Options**:
1. **Overwrite following code** ❌ - We tried this, it crashes
2. **Use trampolines** ❌ - Unused ROM space is too far away (>4KB)
3. **Relocate overwritten code** ⚠️ - Complex, error-prone
4. **Accept we can't inline here** ✅ - Pragmatic choice

### ROM Structure Constraints

**Problem**: Virtua Racing ROM is tightly packed
- No nearby unused space (checked 0x23000-0x30000 range)
- Closest unused: 0x2F5C70 (2.8 MB away!)
- BRA instruction limit: ±4 KB
- JMP requires register setup → overhead defeats optimization

### Assembly-Level Challenges

**SH2 Branching**:
- **BRA**: 12-bit displacement (±2047 instructions × 2 = ±4094 bytes)
- **BSR**: Same range
- **JMP**: Can reach anywhere, but requires:
  ```assembly
  MOV.L @(PC+offset),R1  ; 2 bytes
  JMP @R1                 ; 2 bytes
  NOP                     ; 2 bytes (delay slot)
  .long target_address    ; 4 bytes
  ; Total: 10 bytes vs original 4 bytes = 6 bytes MORE overhead!
  ```

**Conclusion**: Trampolines are worse than the original BSR for distant targets.

---

## Correct Approaches for coord_transform

### Option 1: Accept Reality ✅ **RECOMMENDED**

**Conclusion**: coord_transform cannot be efficiently inlined in this ROM without major restructuring.

**Why**:
- No nearby unused ROM space
- Trampolines add more overhead than they save
- Manual relocation is error-prone and not worth 5% gain

**Action**: Focus on other optimizations with better ROI
**Related**: See `analysis/optimization/FUNC_016_INLINING_INFEASIBILITY.md` for the updated, formal infeasibility analysis.

---

### Option 2: Manual Code Relocation ⚠️ ADVANCED

**If you really want the +5% gain**, you'd need to:

1. **Identify safe relocation target**
   - Find unused space within ±4KB of call sites
   - Or use end of ROM (but far from hot code = cache miss risk)

2. **Relocate overwritten code**
   - Copy destroyed bytes (28 bytes) to new location
   - Update branch targets to point to new location
   - Patch callers to use relocated code

3. **Insert inline code**
   - Place coord_transform body at original call site
   - Add jump to relocated code at end

4. **Update all references**
   - Scan ROM for any jumps/branches to relocated code
   - Update them to new addresses
   - **Very error-prone!**

**Complexity**: High
**Risk**: High (easy to miss a reference)
**Reward**: 5% gain
**Verdict**: Not worth it for this optimization

---

### Option 3: Accept Partial Inline ❓ THEORETICAL

**Idea**: Inline only the most frequently called path

**How**:
```assembly
; Replace BSR with:
    CMP/EQ R14,R14      ; Always true (no-op but sets T flag)
    BT/S inline_code    ; Always taken, but uses delay slot well
    MOV.L @($1C,R14),R1 ; (delay slot - start of coord_transform)

inline_code:
    ; Continue with rest of coord_transform inline...
    ; But we STILL have the expansion problem!
```

**Verdict**: Doesn't solve the core problem

---

## What We Should Do Instead

### Priority 1: unrolled_data_copy FIFO Optimization ⭐⭐⭐

**Why Better**:
- unrolled_data_copy is a **leaf function** (can be modified in isolation)
- **Already fully unrolled** (no code expansion needed)
- Only needs **code modification, not relocation**
- **+10-15% potential gain** (better than coord_transform's +5%)

**What to do**:
1. Profile R13 (stride) value to confirm destination
2. If destination = 0x24000000 (frame buffer):
   - Modify write pattern to batch 4 longs
   - Trigger VDP FIFO optimization
   - Gain: +10-15% in rasterization

**Risk**: Low (modification in place, no expansion)
**Reward**: High (+10-15%)
**Complexity**: Medium (need to understand data flow)

---

### Priority 2: Master/Slave Load Balancing ⭐⭐⭐

**Why Better**:
- **Validated underutilization** (Slave ~0.03% busy) and **working sync protocol** (v2.3 COMM6/COMM4)
- Doesn't require code relocation
- Adds work to idle CPU rather than optimizing busy one

**What to do**:
1. Use cache-through staging (0x2200xxxx) for shared buffers
2. Dispatch Slave work via COMM6, ack via COMM4
3. Validate correctness with memory inspection
4. Measure actual speedup before scaling

**Risk**: Medium (cache coherency and SDRAM contention)
**Reward**: Very High (theoretical +15–50%, see `analysis/architecture/MASTER_SLAVE_ANALYSIS.md`)
**Complexity**: High (requires understanding both CPUs)

---

### Priority 3: Remove Indirect JSR Calls ⭐⭐

**Why Better**:
- Small, localized changes
- No code expansion
- **+2-3% gain** from removing 5-8 cycle overhead

**What to do**:
1. Profile which callbacks are actually used
2. If only 1-2 variants, replace JSR @R14 with:
   ```assembly
   MOV.L @($1C,R14),R0
   CMP/EQ #1,R0
   BT callback1
   BSR callback2
   ```

**Risk**: Low
**Reward**: Medium (+2-3%)
**Complexity**: Low

---

## Lessons for Future Optimizations

### 1. **Profile Before Patching**

- Use emulator debugger to trace actual execution
- Confirm assumptions (call frequency, register values)
- Measure before optimizing

### 2. **Check ROM Structure**

- Verify unused space exists nearby
- Calculate branch distances before coding
- Understand ROM layout constraints

### 3. **Start Small**

- Test one modification at a time
- Verify each change works before proceeding
- Create backups at every step

### 4. **Consider Alternatives**

- Inlining isn't always the answer
- Sometimes algorithmic changes are better
- Multi-CPU utilization often has bigger impact

### 5. **Accept Limitations**

- Some optimizations aren't feasible
- ROI analysis: is 5% gain worth weeks of work?
- Focus on high-impact, low-risk optimizations first

---

## Revised Optimization Roadmap (Historical, superseded by v2.3+)

### Phase 1: Low-Hanging Fruit (Week of 2026-01-06)

1. **Profile unrolled_data_copy parameters** ✅ Easy, high value
   - Determine if FIFO optimization applies
   - Potential: +10-15%

2. **Analyze Master/Slave distribution** ✅ Medium effort, very high value
   - Trace COMM register usage
   - Potential: +20-40%

### Phase 2: Safe Optimizations (Week of 2026-01-13)

3. **Remove indirect JSR calls** ✅ Easy, low risk
   - Profile callback targets
   - Replace with direct calls
   - Potential: +2-3%

4. **Remove redundant operations** ✅ Easy, low risk
   - Remove final stride add in unrolled_data_copy
   - Remove unnecessary pointer resets
   - Potential: +1-2%

### Phase 3: Skip

5. **~~coord_transform inlining~~** ❌ Not feasible without major restructuring

---

## Conclusion

**What we learned**:
- ✅ **Expansion ROM approach WORKS** for standalone functions (vertex_transform proven)
- ❌ quad_helper/018/019 have complex cross-function dependencies - require different strategy
- Trampoline overhead (~4-6 cycles) is acceptable when saving 6+ cycles from inlining
- **Critical**: 4-byte alignment, correct addresses, and instruction encoding verification

**What we gained**:
- **Working proof of concept**: vertex_transform with inlined coord_transform
- Complete understanding of SH2 literal pool alignment requirements
- Validated expansion ROM as optimization workspace
- Reusable trampoline pattern for future optimizations

**What's next**:
1. **Extend coord_transform inlining** to quad_helper/018/019 (complex, may need full block relocation)
2. **Apply same pattern** to other hot functions that can be relocated
3. Master/Slave workload distribution (validated sync; see `analysis/architecture/MASTER_SLAVE_ANALYSIS.md`)

**Savings achieved**:
- vertex_transform optimization: **~4,800 cycles/frame** (1 of 4 call sites)
- Potential with all 4 sites: **~19,200 cycles/frame** (~5% frame budget)

**Overall impact**: POC validates the approach; full implementation could yield **+2-3 FPS**

---

## Testing Notes

**Current ROM Status**:
- ❌ Test ROM (Virtua Racing - Test1.32x): Historical crash (file not in repo)
- ✅ Original ROM: Works perfectly
- ⏳ Future optimized ROM: TBD (use in-place optimizations + Master/Slave approach)

**Next steps (current)**:
1. Use v2.3 sync protocol to offload safe work
2. Validate correctness with memory inspection tooling
3. Measure and document gains per change

---

## ❌ ABANDONED: Phase 11 Code Injection (January 24, 2026)

### Summary

The code injection approach using `phase11_rom_patcher.py` reached its limits and was abandoned in favor of full assembly build.

### What We Tried

Inject hook bytecode at ROM offset 0x596 to intercept Slave SH2 idle polling and redirect to expansion ROM handler.

### Why It Failed

1. **ROM space conflicts**: The injection point (0x596) contains "ROM Version 1.0" string (16 bytes), immediately followed by a 68K function at 0x5A6. Our hook bytecode extended into the 68K function.

2. **PC-relative fragility**: SH2 MOV.L @(disp,PC) requires careful alignment. Multiple versions (v4, v5, v6) had displacement calculation errors.

3. **Literal pool alignment**: 4-byte alignment requirements conflicted with available space between existing code.

4. **Debugging difficulty**: Hand-encoding bytecode is error-prone; each iteration required manual verification.

### Lesson Learned

**Code injection works for small, isolated patches but doesn't scale.**

For significant code changes:
- Use full assembly build (`make all`)
- Modify disassembly sources directly
- Let the assembler handle opcode encoding and alignment
- Test with complete rebuild, not incremental patches

### Correct Approach (Current)

Instead of patching existing ROM, we now:
1. Edit `disasm/sections/` assembly files
2. Add new code to `expansion_300000.asm`
3. Build complete ROM with `make all`
4. Test rebuilt ROM in PicoDrive

---

## Historical Note

This failed optimization attempt is **valuable documentation** for the community:
- Shows why some optimizations aren't feasible
- Explains ROM structure constraints
- Demonstrates proper root cause analysis
- Guides future optimization efforts

**Failure is part of the process** - we learned more from this than we would have from easy success!

---

**Status**: Documented and understood
**Lesson**: Always verify ROM structure before attempting code expansion; prefer full assembly build over injection
**Next**: Continue moving functions to expansion ROM via assembly
