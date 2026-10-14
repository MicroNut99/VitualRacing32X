# coord_transform Inlining Feasibility Analysis

**Date**: January 2026
**Updated**: March 16, 2026
**Status**: ✅ DONE — all 4 call sites optimized (S-6)

> **UPDATE (2026-01-24)**: vertex_transform was successfully optimized using the expansion ROM approach.
>
> **UPDATE (2026-03-16)**: ALL 4 call sites now optimized (S-6). quad_helper-019 state machine
> relocated as a complete 278-byte block to expansion ROM $301300 (388 bytes after inlining).
> 20 branch displacements recalculated programmatically. 6 JMP trampolines at original entry points.
> The "full block relocation" approach recommended below was successfully implemented.

---

## Executive Summary

Investigation into inlining coord_transform at its 4 call sites revealed:

1. **vertex_transform**: ✅ Successfully optimized using expansion ROM approach (2026-01-24)
2. **quad_helper, quad_batch_short, quad_batch_alt_short**: ⚠️ Complex - tightly coupled state machine with shared code paths

The state machine complexity of quad_helper-019, combined with BSR range limitations, makes traditional inlining impractical for those functions. However, **vertex_transform is a standalone function** that was successfully relocated to expansion ROM with coord_transform inlined.

---

## Key Discovery: State Machine Architecture

### Code Structure Analysis

The disassembly reveals the callers share a complex control flow:

```
02223386  RTS                        ; coord_transform ends
02223388  MOV.L R4,@($34,R14)        ; coord_transform's delay slot = first caller instruction
0222338A  STS.L PR,@-R15             ; quad_helper entry point
0222338C  BSR   $02223368            ; quad_helper calls coord_transform
...
02223394  BF    $022233A4            ; quad_helper branches INTO quad_batch_short's body
...
022233A0  RTS                        ; quad_helper exit
022233A2  NOP                        ; quad_helper's delay slot = quad_batch_short entry point
```

### Shared Elements

1. **Delay Slot Sharing**
   - coord_transform's RTS uses delay slot at 0x02223388
   - This instruction is also the first operation of the caller state machine
   - quad_helper's RTS uses delay slot at 0x022233A2
   - That NOP is also quad_batch_short's entry point

2. **Cross-Function Branching**
   - quad_helper @ 0x02223394: `BF $022233A4` branches INTO quad_batch_short's body
   - quad_batch_short/019 share exit path at 0x0222339E
   - Multiple functions converge on common cleanup code

3. **Embedded Data Literals**
   - Literal pools between function segments (0x02223410: `$FF00`, 0x0222344C: `$00FF00FF`)
   - These appear inline within the code stream

---

## Why Inlining Fails

### Constraint 1: No Clean Entry Points

Creating trampolines at quad_helper/018/019 entry points would break cross-function branches:
- A trampoline at 0x0222338A would disrupt the branch at 0x02223394
- quad_batch_short/019 jump back into quad_helper's loop (0x02223390)
- Modifying any entry point breaks the state machine

### Constraint 2: BSR Range Limitation

The SH2 BSR instruction has a range of PC ± 4KB (±2048 words):
- coord_transform callers are at ~0x0222338A
- Expansion space starts at ~0x02300000
- Distance: ~0x100000 (1MB) - **far exceeds BSR range**

To reach expansion space would require:
```assembly
MOV.L  @(disp,PC),R0    ; 2 bytes, 1 cycle - load expansion address
JMP    @R0              ; 2 bytes, 2 cycles
NOP                     ; 2 bytes, 1 cycle - delay slot
```
This adds 4+ cycles overhead, **negating the 6-cycle savings** from eliminating BSR/RTS.

### Constraint 3: No Slack Space

Inlining coord_transform (30 bytes) at each call site would expand code by:
- 30 bytes code - 4 bytes BSR+delay = 26 bytes per site
- 26 bytes × 4 sites = 104 bytes expansion needed

The original ROM has **zero slack bytes** - every byte is used for code or data.

### Constraint 4: Code Density Optimization

The original developers applied extreme code density optimizations:
- Delay slot sharing between unrelated functions
- Branch targets that land mid-function
- State machine patterns spanning multiple "functions"

This is **space-optimized code**, not **speed-optimized code**.

---

## Attempted Approaches

| Approach | vertex_transform | quad_helper-019 | Notes |
|----------|----------|--------------|-------|
| In-place inlining | N/A | FAILED | No room, would overwrite adjacent code |
| Trampoline to expansion | ✅ SUCCESS | FAILED | Works for standalone functions only |
| Caller relocation to expansion | ✅ SUCCESS | FAILED | Cross-function branches break for 017-019 |
| Full block relocation | N/A | TOO RISKY | Would require replicating complex state machine |

**Key insight**: vertex_transform succeeded because it's a **standalone function** without the cross-function dependencies of quad_helper-019.

---

## Recommendations

### Completed ✅
1. **vertex_transform optimization**: Successfully implemented with expansion ROM approach
   - Saves ~4,800 cycles/frame (1 of 4 call sites)
   - See `disasm/sh2/expansion/vertex_transform_optimized.asm`

### Short Term
1. **Apply same pattern** to other standalone hot functions
2. **Profile actual FPS gain** from vertex_transform optimization
3. **Document expansion ROM patterns** for future use

### Long Term (for quad_helper-019)
If optimizing the remaining 3 call sites is a priority:
1. **Full rewrite** of quad_helper-019 complex as a single optimized unit
2. **Relocate entire state machine block** to expansion space
3. **Replicate all cross-function branches** in expansion code
4. **Extensive testing** required due to complexity

This would be a major undertaking requiring deep understanding of the polygon processing state machine, but the vertex_transform POC proves the approach is viable.

---

## Lessons Learned

1. **Hand-optimized assembly is fragile**: The original code trades maintainability for space
2. **Function boundaries are illusions**: Call graph analysis can't reveal shared code paths
3. **Range limitations matter**: SH2's limited branch range constrains optimization options
4. **Space vs speed tradeoff**: Original game chose space, limiting our speed options
5. **Standalone functions CAN be optimized**: vertex_transform proved the expansion ROM approach works
6. **Trampoline overhead is acceptable**: 4-6 cycle overhead is offset by 6+ cycle savings from inlining
7. **4-byte alignment is critical**: MOV.L @(disp,PC) requires aligned literal pools
8. **Verify instruction encoding**: Comments in disassembly may be wrong - always check opcodes

---

## References

- [OPTIMIZATION_LESSONS_LEARNED.md](OPTIMIZATION_LESSONS_LEARNED.md) - Detailed POC implementation
- [SH2_3D_FUNCTION_REFERENCE.md](../sh2-analysis/SH2_3D_FUNCTION_REFERENCE.md)
- [SH2_3D_CALL_GRAPH.md](../sh2-analysis/SH2_3D_CALL_GRAPH.md)
- [OPTIMIZATION_OPPORTUNITIES.md](OPTIMIZATION_OPPORTUNITIES.md)
- Optimized source: `disasm/sh2/expansion/vertex_transform_optimized.asm`
- Expansion ROM: `disasm/sections/expansion_300000.asm`
- Trampoline: `disasm/sections/code_22200.asm` (lines 2322+)
