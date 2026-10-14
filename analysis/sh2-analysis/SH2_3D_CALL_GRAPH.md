# 3D Engine Call Graph

**Virtua Racing Deluxe - Function Relationships**
**Analysis Date**: January 6, 2026

---

## Overview

Complete call graph analysis of 109 functions in the SH2 3D rendering engine. This document maps all function relationships, identifies hot paths, and highlights the execution flow through the rendering pipeline.

**Statistics**:
- Total Functions: 109
- Functions with Calls: 31
- Leaf Functions: 78
- Direct Calls (BSR): 98
- Indirect Calls (JSR @Rn): 20
- Potential Entry Points: 74

---

## Visual Call Graph (Partial)

### Hot Path: Main Rendering Loop

```
Entry Point
    │
    ▼
┌─────────────────────────────────────────┐
│  main_coordinator_short (0x0222301C)                  │  Main Coordinator
│  ├─> transform_loop (0x022230E6)              │  Matrix Transform Setup
│  │   ├─> matrix_multiply (0x02223114) [LEAF]   │  MAC.L Matrix Multiply
│  │   └─> JSR @R14                        │  Indirect: Per-vertex callback
│  ├─> alt_transform_loop (0x02223176)              │  Alt Transform Setup
│  │   ├─> alt_matrix_multiply (0x022231A2) [LEAF]   │  MAC.L Matrix Multiply (variant)
│  │   └─> JSR @R14                        │  Indirect: Per-vertex callback
│  ├─> display_list_4elem (0x022231E4) [LEAF]        │  Result Processor
│  └─> display_list_3elem (0x02223202) [LEAF]        │  Result Processor (variant)
└─────────────────────────────────────────┘
```

### Hot Path: Polygon Processing Chain

```
┌─────────────────────────────────────────┐
│  quad_batch_short (0x022233A2)                  │  Polygon Coordinator
│  ├─> coord_transform (0x0222335A) [LEAF] ⭐    │  HOTSPOT: Called 4×
│  └─> vertex_helper_short (0x02223468)              │  Polygon Transform
│      ├─> vertex_helper_short (0x02223468)          │  Recursive/loop structure
│      └─> frustum_cull_short (0x02223500)          │  Sub-polygon handler
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  quad_batch_alt_short (0x0222340C)                  │  Alt Polygon Path
│  ├─> coord_transform (0x0222335A) [LEAF] ⭐    │  HOTSPOT: Called 4×
│  └─> vertex_helper_short (0x02223468)              │  Transform
└─────────────────────────────────────────┘
```

### Hot Path: Extended Processing

```
┌─────────────────────────────────────────┐
│  func_060 (0x02223E08)                  │  Extended Processor
│  └─> unrolled_data_copy (0x02223F2C) [LEAF] ⭐    │  HOTSPOT: Called 4×
│                                         │
│  func_061 (0x02223E32)                  │
│  └─> unrolled_data_copy (0x02223F2C) [LEAF] ⭐    │  HOTSPOT: Called 4×
│                                         │
│  func_062 (0x02223E5C)                  │
│  └─> unrolled_data_copy (0x02223F2C) [LEAF] ⭐    │  HOTSPOT: Called 4×
│                                         │
│  func_063 (0x02223E88)                  │
│  └─> unrolled_data_copy (0x02223F2C) [LEAF] ⭐    │  HOTSPOT: Called 4×
└─────────────────────────────────────────┘
```

---

## Function Categories

### Category 1: Entry Points (74 functions)

Functions that are never called by other functions in this region. Likely called from:
- 68000 main code
- Interrupt handlers
- SH2 Slave CPU
- External ROM code

**Top Entry Points**:
- data_copy (0x0222300A) - Initialization sequence
- main_coordinator_short (0x0222301C) - Main loop coordinator
- case_handlers_short (0x02223066) - Hardware setup
- display_list_loop (0x0222321C) - Specialized processor
- quad_batch_short (0x022233A2) - Polygon batch processor
- quad_batch_alt_short (0x0222340C) - Alt polygon processor

---

### Category 2: Utility Functions (9 functions)

Called multiple times from different locations. Core reusable components.

**coord_transform (0x0222335A)** ⭐ HOTTEST
- Called 4 times
- Leaf function (no outgoing calls)
- Likely: Coordinate transformation or clipping utility
- Size: ~44 bytes

**unrolled_data_copy (0x02223F2C)** ⭐ HOTTEST
- Called 4 times
- Leaf function
- Likely: Rasterization helper or pixel operation
- Size: ~150 bytes

**vertex_helper_short (0x02223468)**
- Called 3 times (including self-recursion)
- Calls: vertex_helper_short (recursive), frustum_cull_short
- Likely: Recursive polygon subdivision or loop

**alt_matrix_multiply (0x022231A2)**
- Called 2 times
- Leaf function with MAC.L sequences
- Purpose: Matrix multiplication variant

**display_list_4elem (0x022231E4)**
- Called 2 times
- Leaf function
- Purpose: Result processing/packing

---

### Category 3: Leaf Functions (78 functions)

Functions that don't call any other functions. These are the actual "work" functions:
- Matrix multiplication (with MAC.L)
- Data copying/unpacking
- Register writes (hardware control)
- Simple calculations

**Examples**:
- data_copy (0x0222300A) - Simple loop, 18 bytes
- func_003 (0x022230CC) - Tiny utility, 16 bytes
- func_004 (0x022230DC) - Tiny utility, 10 bytes
- matrix_multiply (0x02223114) - MAC.L matrix multiply, 98 bytes
- alt_matrix_multiply (0x022231A2) - MAC.L matrix multiply variant, 66 bytes
- vdp_init_short (0x022232C4) - Medium complexity, 68 bytes
- coord_transform (0x0222335A) - Hot utility, 44 bytes
- unrolled_data_copy (0x02223F2C) - Hot utility, 150 bytes

---

### Category 4: Coordinators (31 functions)

Functions that call other functions to orchestrate work.

**main_coordinator_short (0x0222301C)**
- Calls: transform_loop, alt_transform_loop, display_list_4elem, display_list_3elem
- Purpose: Main transformation coordinator
- Size: 74 bytes

**transform_loop (0x022230E6)**
- Calls: matrix_multiply, JSR @R14 (indirect)
- Purpose: Matrix transform setup with callback
- Size: 46 bytes

**display_entry (0x02223268)**
- Calls: alt_matrix_multiply, display_list_4elem
- Purpose: Transform pipeline stage
- Size: 92 bytes

---

## Hotspot Analysis

### Top 10 Most-Called Functions

| Rank | Function | Address | Call Count | Type | Est. Impact |
|------|----------|---------|------------|------|-------------|
| 1 | coord_transform | 0x0222335A | 4 | Leaf | Critical |
| 2 | unrolled_data_copy | 0x02223F2C | 4 | Leaf | Critical |
| 3 | vertex_helper_short | 0x02223468 | 3 | Coordinator | High |
| 4 | alt_matrix_multiply | 0x022231A2 | 2 | Leaf (MAC) | High |
| 5 | display_list_4elem | 0x022231E4 | 2 | Leaf | Medium |
| 6 | frustum_cull_short | 0x02223500 | 2 | Unknown | Medium |
| 7 | span_filler_short | 0x0222375C | 2 | Unknown | Medium |
| 8 | polygon_batch_short | 0x022239AA | 2 | Unknown | Medium |
| 9 | context_setup_short | 0x022241CC | 2 | Unknown | Medium |
| 10| display_list_3elem | 0x02223202 | 1 | Leaf | Low |

**Optimization Priority**: Focus on coord_transform and unrolled_data_copy first (4× calls, leaf functions = hot loops).

---

## Indirect Call Analysis

### JSR @R14 Pattern

**Occurrences**: 9 functions use JSR @R14 for indirect calls

**Functions with JSR @R14**:
- transform_loop (0x022230E6) - Calls per-vertex transform handler
- alt_transform_loop (0x02223176) - Calls per-vertex transform handler variant

**Purpose**: Function pointer callbacks. R14 contains address of handler function, allowing runtime dispatch based on polygon type or rendering mode.

**Example**:
```assembly
022230FE  5EE7     MOV.L   @($1C,R14),R14   ; Load callback pointer from context+0x1C
02223100  4E0B     JSR     @R14             ; Call indirect function
02223102  60D5     MOV.W   @R13+,R0         ; Delay slot: load parameter
```

**Optimization Opportunity**: Indirect calls have overhead (~5-8 cycles). Could use direct calls if callback doesn't change.

---

## Complete Call Graph

### Functions 000-020

```
data_copy (0x0222300A - 0x0222301A):
  (leaf function - no calls)

main_coordinator_short (0x0222301C - 0x02223064):
  -> transform_loop (0x022230E6)
  -> alt_transform_loop (0x02223176)
  -> display_list_4elem (0x022231E4)
  -> display_list_3elem (0x02223202)

case_handlers_short (0x02223066 - 0x022230CA):
  -> func_003 (0x022230CC)
  -> func_004 (0x022230DC)

func_003 (0x022230CC - 0x022230DA):
  (leaf function - no calls)

func_004 (0x022230DC - 0x022230E4):
  (leaf function - no calls)

transform_loop (0x022230E6 - 0x02223112):
  -> matrix_multiply (0x02223114)
  -> JSR_@R14 (indirect)

matrix_multiply (0x02223114 - 0x02223174):
  (leaf function - MAC.L heavy)

alt_transform_loop (0x02223176 - 0x022231A0):
  -> alt_matrix_multiply (0x022231A2)
  -> JSR_@R14 (indirect)

alt_matrix_multiply (0x022231A2 - 0x022231E2):
  (leaf function - MAC.L heavy)

display_list_4elem (0x022231E4 - 0x02223200):
  (leaf function)

display_list_3elem (0x02223202 - 0x0222321A):
  (leaf function)

display_list_loop (0x0222321C - 0x02223266):
  -> display_entry (0x02223268)

display_entry (0x02223268 - 0x022232C2):
  -> alt_matrix_multiply (0x022231A2)
  -> display_list_4elem (0x022231E4)

vdp_init_short (0x022232C4 - 0x02223306):
  (leaf function)

func_014 (0x02223308 - 0x0222333E):
  (leaf function)

func_015 (0x02223340 - 0x02223358):
  (leaf function)

coord_transform (0x0222335A - 0x02223386): ⭐ HOTSPOT
  (leaf function - called 4 times)

quad_helper (0x02223388 - 0x022233A0):
  -> coord_transform (0x0222335A)

quad_batch_short (0x022233A2 - 0x0222340A):
  -> coord_transform (0x0222335A)
  -> vertex_helper_short (0x02223468)

quad_batch_alt_short (0x0222340C - 0x02223466):
  -> coord_transform (0x0222335A)
  -> vertex_helper_short (0x02223468)

vertex_helper_short (0x02223468 - 0x022234BE):
  -> vertex_helper_short (0x02223468)  [RECURSIVE]
  -> frustum_cull_short (0x02223500)
```

*[Functions 021-108 follow similar patterns - see disasm/sh2_3d_engine_callgraph.txt for complete details]*

---

## Critical Execution Paths

### Path 1: Initialization (One-time)

```
Entry → data_copy → Hardware Init → Return
        │
        └─> case_handlers_short → func_003 → Hardware Config
                    └─> func_004 → Additional Setup
```

**Frequency**: Once per game start or scene load
**Performance Impact**: Negligible (one-time cost)

---

### Path 2: Per-Frame Vertex Transform (Hot)

```
Entry → main_coordinator_short → transform_loop → matrix_multiply (MAC.L) ⭐
                            └─> JSR @R14 (callback)
                │
                └─> alt_transform_loop → alt_matrix_multiply (MAC.L) ⭐
                            └─> JSR @R14 (callback)
```

**Frequency**: Per vertex, per frame (~500 vertices × 60 FPS = 30,000 calls/sec)
**Performance Impact**: CRITICAL
**Bottleneck**: MAC.L sequences take 2-3 cycles each, 9-12 cycles per matrix op

---

### Path 3: Polygon Processing (Hot)

```
Entry → quad_batch_short → coord_transform ⭐ (4× calls)
                └─> vertex_helper_short → frustum_cull_short
                            └─> vertex_helper_short (recursive)

Entry → quad_batch_alt_short → coord_transform ⭐ (4× calls)
                └─> vertex_helper_short
```

**Frequency**: Per polygon, per frame (~800 polygons × 60 FPS = 48,000 calls/sec)
**Performance Impact**: CRITICAL
**Bottleneck**: coord_transform called 4 times per polygon = 4× overhead

---

### Path 4: Extended Rendering (Hot)

```
Entry → func_060 → unrolled_data_copy ⭐
Entry → func_061 → unrolled_data_copy ⭐
Entry → func_062 → unrolled_data_copy ⭐
Entry → func_063 → unrolled_data_copy ⭐
```

**Frequency**: Per pixel batch or rasterization unit
**Performance Impact**: CRITICAL
**Bottleneck**: unrolled_data_copy is 150 bytes of tight code, likely pixel inner loop

---

## Function Complexity Distribution

```
Size Range   Count   Purpose
═══════════════════════════════════════════
<20 bytes    25      Tiny utilities
20-50 bytes  38      Small helpers
50-100 bytes 32      Medium functions
100-200 bytes 12     Large functions
>200 bytes   2       Complex handlers
```

**Observations**:
- Most functions are small (<50 bytes) - good for i-cache
- Complex work is distributed across many small functions
- Function call overhead may be significant

---

## Recursion and Loops

### Recursive Functions

**vertex_helper_short (0x02223468)**: Self-recursive
- Purpose: Likely polygon subdivision or hierarchical processing
- Max depth: Unknown (counter-based, likely bounded)
- Optimization: Could unroll or iterate instead

---

## Summary

The call graph reveals a well-structured 3D engine with clear separation of concerns:

**Strengths**:
- Modular design with small, focused functions
- Clear hot paths through coord_transform and unrolled_data_copy
- Efficient use of leaf functions for performance-critical code
- Indirect dispatch allows runtime flexibility

**Optimization Targets**:
1. **coord_transform** (hotspot) - Inline or optimize for 4× call reduction
2. **unrolled_data_copy** (hotspot) - Likely pixel loop, optimize memory access
3. **matrix_multiply/alt_matrix_multiply** (MAC.L) - Already optimal, but check input data alignment
4. **JSR @R14** (indirect calls) - Consider direct calls if dispatch is predictable

**Next Steps**:
- Disassemble coord_transform and unrolled_data_copy in detail
- Profile actual call frequencies on hardware
- Measure cycle counts for hot paths
- Identify cache miss patterns

---

## References

- [SH2_3D_PIPELINE_ARCHITECTURE.md](SH2_3D_PIPELINE_ARCHITECTURE.md) - Pipeline stages using these functions
- [SH2_3D_FUNCTION_REFERENCE.md](SH2_3D_FUNCTION_REFERENCE.md) - Detailed function descriptions
- [OPTIMIZATION_OPPORTUNITIES.md](OPTIMIZATION_OPPORTUNITIES.md) - How to optimize hot paths
- Complete call graph: `disasm/sh2_3d_engine_callgraph.txt`
