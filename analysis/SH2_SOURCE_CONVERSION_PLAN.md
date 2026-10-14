# SH2 Source Conversion Plan

**Objective:** Convert SH2 binary blobs to proper assembly source for modification and optimization

**Date:** 2026-01-23

---

## Current State

### What We Have

1. **Annotated disassembly** ([sh2_3d_engine_annotated.asm](../disasm/sh2_3d_engine_annotated.asm))
   - 109 functions documented
   - Full register usage analysis
   - Call graph mapped
   - Fixed-point arithmetic understood

2. **Binary blobs in build** ([sections/code_222200.asm](../disasm/sections/code_222200.asm))
   ```assembly
   org $222200
   dc.w $A000    ; Opaque 16-bit words
   dc.w $01C0    ; Not modifiable
   dc.w $01B0    ; Not optimizable
   ```

3. **Phase 17.1/17.2 proof-of-concept**
   - Cycle measurement works (FRT timer)
   - Slave CPU communication proven
   - Master/Slave comparison methodology established
   - **Limited by binary injection fragility**

### What We Need

**Source-level control** of SH2 code, like Sega/Yu Suzuki had:
- C for high-level logic
- Assembly for performance-critical sections
- Proper build system that links everything

---

## The Problem with Binary Injection

Phase 17.2 revealed fundamental issues:

### Issue 1: PC-Relative Code Doesn't Relocate
```assembly
; Original at 0x020243E0
MOV.L @(disp,PC),R1    ; Loads from PC+offset
JMP @R1                 ; Jumps to address

; Copied to 0x02300210
MOV.L @(disp,PC),R1    ; NOW WRONG! PC changed, literal pool is elsewhere
JMP @R1                 ; Jumps to garbage
```

### Issue 2: Hook Chain Fragility
- Phase 15 FPS counter hooks VBlank → 0x02300040
- Phase 17.2 hooks VBlank → 0x02300200 → tries to call 0x02300040
- VBlank chain breaks, rendering stops
- Debugging requires disassembling redirects to find actual handlers

### Issue 3: No Review/Maintenance
- Binary blobs in Python scripts
- Can't read the code
- Can't review changes
- Can't maintain long-term

**Conclusion:** Binary injection was useful for proof-of-concept, but has reached its limit.

---

## Proposed Solution: Proper SH2 Source Assembly

### Phase 18: Convert Critical Functions to Source

**Target functions** (from [SLAVE_INTEGRATION_RESEARCH.md](SLAVE_INTEGRATION_RESEARCH.md)):

| Function | Address | Size | Purpose | Priority |
|----------|---------|------|---------|----------|
| transform_loop | 0x022230E6 | 46 B | Transform loop | HIGH |
| matrix_multiply | 0x02223114 | 98 B | Matrix multiply (hot path) | HIGH |
| alt_transform_loop | 0x02223176 | 44 B | Alt transform loop | MEDIUM |
| alt_matrix_multiply | 0x022231A2 | 66 B | Alt matrix multiply | MEDIUM |
| main_coordinator_short | 0x0222301C | 74 B | Display list processor | LOW (complex) |

**Start with matrix_multiply** - it's a leaf function (no calls), pure math, well understood.

### Implementation Steps

#### 1. Create Proper Assembly Source

Create [disasm/sh2/matrix_multiply.asm](../disasm/sh2/matrix_multiply.asm):

```assembly
; ============================================================================
; Matrix × Vector Multiplication (matrix_multiply)
; ============================================================================
; Address: 0x02223114 (ROM: 0x223114)
; Size: 98 bytes
; ============================================================================
;
; Purpose: Transform 3D vector using 4×4 matrix (3×3 rotation + translation)
;          Uses SH2 MAC (Multiply-Accumulate) for efficient fixed-point math
;
; Formula: V_out = M × V_in + T
;
; Fixed-Point: 16.16 (16 int bits, 16 frac bits)
;
; Input:
;   R4 = Pointer to 4×4 matrix (row-major, 4 longs per row)
;   R5 = Pointer to input vector (3 longs: X, Y, Z)
;   R6 = Pointer to output buffer
;   R7 = Additional parameter
;
; Output:
;   Transformed vector at R6:
;     @(0,R6) = X'
;     @(16,R6) = Y'
;     @(20,R6) = Z'
;
; Clobbers: R0, R1, R2, R3, R4, R5, R7, R8, MACH, MACL
; ============================================================================

matrix_multiply:
    ; Transform X: X' = M[0][0]*X + M[0][1]*Y + M[0][2]*Z + T[0]
    mac.l   @r4+,@r5+           ; MAC += M[0][0] * V[0]
    mac.l   @r4+,@r5+           ; MAC += M[0][1] * V[1]
    mac.l   @r4+,@r5+           ; MAC += M[0][2] * V[2]
    add     #-12,r5             ; Reset R5 to vector start
    mov.l   @r4+,r8             ; R8 = T[0] (translation X)
    add     #-48,r4             ; Adjust matrix pointer
    sts     mach,r0             ; Extract high 32 bits
    sts     macl,r3             ; Extract low 32 bits
    xtrct   r0,r3               ; R3 = MAC[47:16] (16.16 result)
    add     r8,r3               ; R3 += T[0]
    mov.l   r3,@r6              ; Store X'
    mov.l   r7,@(16,r6)         ; Store param
    mov.l   r0,@(20,r6)         ; Store value
    clrmac                      ; Clear for next operation

    ; Transform Y: Y' = M[1][0]*X + M[1][1]*Y + M[1][2]*Z + T[1]
    mac.l   @r4+,@r5+
    mac.l   @r4+,@r5+
    mac.l   @r4+,@r5+
    add     #-12,r5
    mov.l   @r4+,r8
    sts     mach,r0
    sts     macl,r1
    xtrct   r0,r1
    add     r8,r1

    ; Transform Z: Z' = M[2][0]*X + M[2][1]*Y + M[2][2]*Z + T[2]
    clrmac
    mac.l   @r4+,@r5+
    mac.l   @r4+,@r5+
    mac.l   @r4+,@r5+
    add     #-12,r5
    mov.l   @r4+,r8
    sts     mach,r0
    sts     macl,r2
    xtrct   r0,r2
    add     r8,r2

    ; Store Y' and Z'
    mov.l   r1,@(4,r6)
    mov.l   r2,@(8,r6)

    rts
    nop
```

#### 2. Set Up SH2 Assembler

Update [Makefile](../Makefile):

```make
# SH2 assembler (vasm)
SH2_AS = tools/vasmsh2_std
SH2_ASMFLAGS = -Fbin -m7095 -no-opt -spaces -quiet

# SH2 source files
SH2_MATRIX_SRC = disasm/sh2/matrix_multiply.asm
SH2_MATRIX_OBJ = $(BUILD_DIR)/sh2_matrix.bin

# Assemble SH2 code
$(SH2_MATRIX_OBJ): $(SH2_MATRIX_SRC)
	@echo "==> Assembling SH2 code..."
	$(SH2_AS) $(SH2_ASMFLAGS) -o $@ $<
```

#### 3. Integrate into ROM Build

Modify [sections/code_222200.asm](../disasm/sections/code_222200.asm):

```assembly
org $222200

; Original binary blob up to matrix_multiply
dc.w $A000, $01C0, $01B0, ...  ; (up to 0x223114)

; === FUNC_006: Matrix Multiply (MODIFIABLE SOURCE) ===
        org $223114
        incbin "../build/sh2_matrix.bin"  ; Assembled from matrix_multiply.asm

; Resume original binary blob after matrix_multiply
        org $223176
dc.w $2FE6, $4F22, ...         ; alt_transform_loop and beyond
```

#### 4. Verify Byte-Accurate Reassembly

```bash
# Build ROM with new source
make clean && make

# Compare matrix_multiply bytes
cmp -l "Virtua Racing Deluxe (USA).32x" build/vr_rebuild.32x | \
    awk '$1 >= 0x223114 && $1 < 0x223176 { print }'

# Should show NO differences if source matches original
```

#### 5. Optimize matrix_multiply

Once we have working source, we can optimize:

**Current code:**
- Pointer resets: `ADD #-12,R5` after every dot product (wastes cycles)
- Matrix pointer adjustment: `ADD #-48,R4` (unnecessary)

**Optimized approach:**
- Restructure memory layout to eliminate resets
- Use register shuffling instead of pointer arithmetic
- Unroll small loops for better pipeline utilization

---

## Benefits of This Approach

### Immediate

1. **Readable code** - Can review and understand changes
2. **Modifiable** - Change algorithms, not binary blobs
3. **Maintainable** - Source control, diff, merge
4. **Testable** - Assemble, test, verify byte-accurate

### Long-term

1. **True optimization** - Modify hot paths (matrix_multiply is 47% of transform time)
2. **Slave parallelization** - Split transform work between Master/Slave
3. **Interrupt-driven VDP** - Replace polling with H-INT (40% speedup)
4. **Algorithm improvements** - Better culling, LOD, etc.

---

## Estimated Effort

| Phase | Task | Effort | Risk |
|-------|------|--------|------|
| 18.1 | Set up vasm SH2 assembler | 1 hour | LOW |
| 18.2 | Convert matrix_multiply to source | 2 hours | LOW (leaf function) |
| 18.3 | Verify byte-accurate build | 1 hour | LOW |
| 18.4 | Optimize matrix_multiply (pointer resets) | 3 hours | MEDIUM |
| 18.5 | Convert transform_loop (loop) | 3 hours | MEDIUM (indirect calls) |
| 18.6 | Test with real game | 2 hours | MEDIUM |
| **Total** | **~12 hours** | **MEDIUM** |

---

## Success Criteria

- [ ] matrix_multiply assembles from source
- [ ] Byte-accurate match with original ROM
- [ ] ROM boots and renders correctly
- [ ] Can modify source and reassemble
- [ ] Optimization shows measurable cycle reduction

---

## Alternative: Full C Rewrite (Long-term)

For major improvements, we could rewrite the entire 3D engine in C:

**Advantages:**
- Modern toolchain (GCC for SH2)
- Higher-level optimizations
- Easier to maintain

**Disadvantages:**
- Large upfront effort (~200+ hours)
- Compiler may not match hand-optimized assembly performance
- Risk of subtle behavioral differences

**Recommendation:** Start with assembly source control (Phase 18), consider C rewrite for Phase 20+.

---

## Next Steps

1. **Install vasm SH2 assembler**
   ```bash
   cd tools
   wget http://sun.hasenbraten.de/vasm/release/vasm.tar.gz
   tar xzf vasm.tar.gz
   cd vasm
   make CPU=sh2 SYNTAX=std
   cp vasmsh2_std ../../tools/
   ```

2. **Create matrix_multiply source** (as shown above)

3. **Integrate into build** (Makefile + section includes)

4. **Verify byte-accurate** (compare with original ROM)

5. **Optimize** (remove pointer resets, measure cycles)

---

## References

- [sh2_3d_engine_annotated.asm](../disasm/sh2_3d_engine_annotated.asm) - Annotated disassembly
- [SLAVE_INTEGRATION_RESEARCH.md](SLAVE_INTEGRATION_RESEARCH.md) - Transform pipeline analysis
- [SH2_3D_FUNCTION_REFERENCE.md](sh2-analysis/SH2_3D_FUNCTION_REFERENCE.md) - Function catalog
- [32x-hardware-manual.md](../docs/32x-hardware-manual.md) - SH2 instruction set

---

**Status:** Ready to start Phase 18 - Proper SH2 source assembly
