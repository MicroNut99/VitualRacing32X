# SH2 Translation Integration — Final Status

**Last Updated:** 2026-02-28
**Status:** COMPLETE — All 92 function IDs integrated

## Overview

All 92 SH2 3D engine function IDs (data_copy through poll_copy_short) are fully integrated into the build system. Source files in `disasm/sh2/3d_engine/` are assembled via Makefile rules into `.inc` files (in `disasm/sh2/generated/`) which are included by the ROM section files.

## Integration Summary

| Category | Count | Details |
|----------|-------|---------|
| Individual .inc files | 74 | data_copy through poll_copy_short (some grouped) |
| Grouped into combined .inc | 12 | func_003+004, func_014+015, func_027+028 (in 026), func_029+030+031, func_037+038+039 |
| Numbering gaps (no address space) | 2 | func_035, func_064 |
| Covered by existing includes | 8 | func_056-059 (by unrolled_copy_short+065), func_060-063 (by offset_bsr_short-054) |
| Expansion ROM functions | 12 | batch_copy_handler, cmd22_single_shot, cmd27_queue_drain, etc. |
| **Total function IDs** | **92** | **All accounted for** |

## Function ID Accounting

### Grouped Functions

These function IDs are combined into a single .inc file because they share code paths:

| .inc File | Contains | Notes |
|-----------|----------|-------|
| offset_copy_short.inc | func_003, func_004 | Offset copy pair |
| vdp_copy_short.inc | func_014, func_015 | VDP copy pair |
| bounds_compare_short.inc | bounds_compare_short, func_027, func_028 | Bounds compare + 2 shared exit paths |
| visibility_short.inc | func_029, func_030, func_031 | Visibility + shared exit paths |
| helpers_short.inc | func_037, func_038, func_039 | Helper trio |

### Numbering Gaps

These function IDs do not correspond to any address space in the ROM:

| ID | Between | Explanation |
|----|---------|-------------|
| func_035 | span_filler_short ($237D5) → render_dispatch_short ($237D6) | Contiguous — no gap |
| func_064 | unrolled_copy_short ($23F2B) → unrolled_data_copy ($23F2C) | Contiguous — no gap |

### Subsumed Functions

These function IDs were originally identified as separate entry points but are covered by the address ranges of other integrated functions:

| IDs | Covered By | Explanation |
|-----|-----------|-------------|
| func_056-059 | unrolled_copy_short + unrolled_data_copy | Makefile: "func_056 removed — code at $023F2E already covered by unrolled_data_copy" |
| func_060-063 | offset_bsr_short-054 | `raster_batch.asm` is documentation only (header: "DOCUMENTATION ONLY — not used by build system") |

## Assembler Padding Issue — RESOLVED

### Problem

The `sh-elf-as` assembler adds implicit alignment padding that causes byte-level size mismatches with the original ROM layout. This blocked early integration of main_coordinator_short (+1 byte) and case_handlers_short (+9 bytes).

### Solution: `.short` Format

Functions are written using raw `.short` hex opcodes instead of mnemonics, bypassing all assembler padding/alignment behavior:

```assembly
/* Instead of: */
mov.l   @r15+,r8
rts

/* Use: */
.short  0x68F6    /* mov.l @r15+,r8 */
.short  0x000B    /* rts */
```

**46 of 74 .inc files** use this `_short.asm` format. The remaining 28 use mnemonic format with linker scripts.

### Linker Scripts

Functions assembled from mnemonics require `.lds` linker scripts to force assembly at their exact ROM file offset (for correct PC-relative addressing):

```ld
SECTIONS
{
    . = 0x23024;  /* ROM file offset */
    .text : SUBALIGN(2) { *(.text) }
}
```

## Build Pipeline

```
disasm/sh2/3d_engine/func_NNN_*.asm     (source)
    → sh-elf-as → build/sh2/func_NNN.o  (object)
    → sh-elf-ld -T func_NNN.lds         (link at correct offset)
    → sh-elf-objcopy → build/sh2/func_NNN.bin  (raw binary)
    → tools/bin2dcw.py → disasm/sh2/generated/func_NNN.inc  (dc.w include)
    → included by disasm/sections/code_22200.asm (ROM section)
```

## Known Pitfalls

1. **`.align N` uses power-of-2**: `.align 1`=2B, `.align 2`=4B, `.align 4`=16B
2. **MOV @(disp,Rm) expects byte offsets**: `mov.w @(2,r8),r0` = byte offset 2, not scaled
3. **Literal pool sharing**: `MOV.L @(disp,PC)` instructions share data — scan for `$Dnxx` opcodes before overwriting any address
4. **BSR in isolation**: External BSR targets can't resolve — use `.short` with raw opcode

## Related Documentation

- [SH2_3D_PIPELINE_ARCHITECTURE.md](SH2_3D_PIPELINE_ARCHITECTURE.md) — 3D engine architecture
- [../../KNOWN_ISSUES.md](../../KNOWN_ISSUES.md) — SH2 assembly translation pitfalls
- [../../CLAUDE.md](../../CLAUDE.md) — Build instructions and ground rules
