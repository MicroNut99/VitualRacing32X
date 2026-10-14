# VRD PC-Level Profiling - Corrected Results with Memory Regions

**Date:** 2026-01-27
**Tool:** libretro PicoDrive with FULL 32-bit PC capture
**Duration:** 2400 frames (40 seconds @ 60fps) with automated gameplay
**Fix Applied:** Removed PC masking artifact - now captures full memory region information

---

## Executive Summary - CORRECTED

**CRITICAL FINDING:** Slave SH2 spends **66.5% of cycles at SDRAM address 0x0600060A** - a tight loop in game code.

**Key Corrections from Initial Analysis:**
- ❌ **Previous:** PC 0x00060A appeared to be in low memory (BIOS/ROM confusion)
- ✅ **Corrected:** Full PC is **0x0600060A in SDRAM** (game code loaded from ROM)
- ✅ **Discovered:** Cache-through ROM execution (0xC0xxxxxx addresses) accounts for additional cycles

---

## Memory Region Breakdown

### SH2 Memory Map
```
0x00000000-0x00000FFF   BIOS (internal ROM)
0x02000000-0x023FFFFF   Cartridge ROM
0x06000000-0x060FFFFF   SDRAM (game code/data)
0xC0000000-0xC0FFFFFF   Cache-through ROM (faster execution)
```

### Slave SH2 Execution Distribution
```
SDRAM (0x06xxxxxx):  513,515,228 cycles (71.4%)  ← Game code in fast RAM
ROM-C (0xC0xxxxxx):  205,784,971 cycles (28.6%)  ← Cached ROM execution
BIOS (0x000000xx):           257 cycles ( 0.0%)  ← Negligible
```

---

## Slave SH2 Top 10 Hotspots (Corrected)

```
    PC        Region    Total Cycles    Count      Avg     Share   Cumulative
----------  --------  --------------  ----------  ------  ------  ----------
0x0600060A  SDRAM       478,347,505   1,237,151   386.7  66.50%   66.50%  ← PRIMARY
0xC0000196  ROM-C        36,747,231     274,013   134.1   5.11%   71.61%
0xC000019A  ROM-C        23,562,846      52,483   449.0   3.28%   74.89%
0x0600450A  SDRAM        22,871,918      88,383   258.8   3.18%   78.07%
0x06000608  SDRAM        13,803,831      34,308   402.4   1.92%   79.99%  ← 2 bytes before PRIMARY
0xC00000B8  ROM-C        11,458,772      25,860   443.1   1.59%   81.58%
0x06003A4A  SDRAM        10,644,436      24,547   433.6   1.48%   83.06%
0xC00001A8  ROM-C         9,706,614      22,023   440.7   1.35%   84.41%
0xC0000210  ROM-C         7,124,540      15,524   458.9   0.99%   85.40%
0xC00000B4  ROM-C         7,055,306      18,533   380.7   0.98%   86.38%
```

---

## Master SH2 Top 10 Hotspots

```
    PC        Region    Total Cycles    Count    Avg     Share   Cumulative
----------  --------  --------------  --------  ------  ------  ----------
0x0600424E  SDRAM        45,940,249   100,225   458.4  13.73%   13.73%
0x0600450A  SDRAM        35,832,731   139,320   257.2  10.71%   24.43%
0xC000019A  ROM-C        33,630,153    76,366   440.4  10.05%   34.48%
0x06003FDC  SDRAM        22,181,852    48,339   458.9   6.63%   41.11%
0xC0000210  ROM-C         8,959,231    20,768   431.4   2.68%   43.79%
0xC000013C  ROM-C         8,402,503    17,898   469.5   2.51%   46.30%
0x060051CA  SDRAM         8,134,033    21,230   383.1   2.43%   48.73%
0xC00002CC  ROM-C         7,498,924    28,821   260.2   2.24%   50.97%
0xC0000376  ROM-C         7,027,253    28,871   243.4   2.10%   53.07%
0xC0000028  ROM-C         5,535,603    16,848   328.6   1.65%   54.72%
```

---

## Analysis

### 1. SDRAM 0x0600060A is a Tight Loop

**Evidence:**
- PC 0x0600060A: 478M cycles (66.5% of Slave work)
- PC 0x06000608: 14M cycles (1.9%) - **2 bytes before hotspot**
- High average cycles per call: 387 cycles

**Likely scenarios:**
1. **Polling loop** - Waiting on COMM register or VDP status
2. **VDP wait loop** - Waiting for frame buffer access
3. **Sync primitive** - Master/Slave synchronization point

### 2. Memory Region Distribution

**Slave CPU execution:**
- 71.4% in SDRAM (fast cached RAM)
- 28.6% in cache-through ROM (optimized ROM access)

**Master CPU execution:**
- Similar SDRAM/ROM-C distribution

**Implication:** VRD uses SDRAM heavily for performance-critical code

### 3. Shared Code Between CPUs

**Both CPUs execute:**
- 0xC000019A (ROM-C) - Master: 10.1%, Slave: 3.3%
- 0xC0000210 (ROM-C) - Master: 2.7%, Slave: 1.0%
- 0x0600450A (SDRAM) - Master: 10.7%, Slave: 3.2%

**Interpretation:** Shared functions/libraries in ROM and SDRAM

---

## Next Steps

### 1. Identify SDRAM 0x0600060A Source

**Need to determine:**
- What ROM code was copied to SDRAM offset 0x60A?
- What does this code do?
- Is it a polling loop that can be eliminated?

**Approach:**
- Find SDRAM initialization code in ROM
- Trace what gets copied to 0x06000000 base
- Disassemble the source code

### 2. Dynamic Analysis

**If static analysis insufficient:**
- Use PicoDrive debugger to inspect registers at 0x0600060A
- Check what memory locations are being accessed
- Determine if it's waiting on specific condition

### 3. Confirm Loop Type

**Three scenarios:**
| Type | Evidence | Fix Strategy |
|------|----------|--------------|
| COMM polling | Reads 0x2000402x | Use interrupt-driven approach |
| VDP wait | Reads VDP status | Optimize frame buffer access |
| Sync primitive | Reads shared flag | Redesign synchronization |

---

## Performance Implications

### If 0x0600060A is a Polling Loop

**Current:**
```
Slave: 300K cycles/frame
  - 200K in polling (66.5%)
  - 100K actual work
```

**If eliminated:**
```
Slave: 100K cycles/frame (real work only)
FPS gain: 24 → 60+ FPS (BREAKTHROUGH)
```

### If 0x0600060A is VDP Wait

**Current:**
```
Slave blocked on VDP access
Bottleneck: Hardware (cannot fix via software)
```

**Alternative:**
```
Overlap VDP waits with other work
Use asynchronous VDP access patterns
```

---

## Commit Summary

**Profiler fix applied:**
- Removed `pc & 0x00FFFFFF` masking
- Now stores full 32-bit PC
- Export format changed: 6-digit → 8-digit hex
- Added memory region identification

**New findings:**
- Confirmed SDRAM execution dominance (71.4%)
- Identified cache-through ROM usage (28.6%)
- Pinpointed exact bottleneck location with full address context

---

**Document Status:** Profiler corrected - awaiting SDRAM-to-ROM mapping
**Impact:** CRITICAL - Exact bottleneck location confirmed at 0x0600060A
**Confidence:** VERY HIGH - Full PC capture eliminates ambiguity
**Next Phase:** Map SDRAM 0x0600060A back to ROM source and disassemble
