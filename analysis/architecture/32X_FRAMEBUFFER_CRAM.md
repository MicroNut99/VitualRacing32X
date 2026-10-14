# 32X Frame Buffer and CRAM (Color Palette) Reference

**Last Updated**: February 8, 2026

## Overview

The 32X VDP provides dual 1-Mbit frame buffers with line table addressing and a shared 256-entry color palette (CRAM). This document covers frame buffer structure, CRAM format, and access protocols discovered during VRD disassembly and FPS counter implementation.

---

## Frame Buffer Architecture

### Memory Layout

**68K Address Space:**
- **FB0 (Frame Buffer 0)**: `$840000` - `$85FFFF` (128 KB)
- **FB1 (Frame Buffer 1)**: `$860000` - `$87FFFF` (128 KB)
- **Overwrite Area**: Same addresses, special write behavior (see below)

**Key Point:** `$840000` and `$860000` are **FIXED mappings** on the 68K bus. The FS bit (Frame Select) in `$A1518B` controls which buffer the VDP scans out for display, NOT which address maps where.

### Frame Buffer Structure (Packed Pixel Mode)

```
Offset     Size        Description
--------   ---------   ------------------------------------------
$0000      512 bytes   Line Table (256 words, one per scanline)
$0200+     Variable    Pixel Data (referenced by line table)
```

**Line Table Format:**
- 256 word entries (one per scanline 0-223, padded to 256)
- Each entry: 16-bit offset pointing to pixel data within the frame buffer
- Valid entries must be ≥ `$0200` (past the 512-byte line table itself)
- VRD uses linear layout: line N starts at `$2000 + (N × 320)`

**Pixel Data Format (Packed Pixel Mode, 8bpp):**
- 1 byte per pixel = palette index (0-255)
- 320 pixels per line × 224 lines = 71,680 bytes
- Total with line table: ~72 KB per frame buffer

### Display Modes

| Mode | Bits/Pixel | Colors | Description |
|------|-----------|--------|-------------|
| **Direct Color** | 16 | 32,768 | RGB555 color per pixel, no palette |
| **Packed Pixel** | 8 | 256 from 32K | Palette index per pixel (VRD uses this) |
| **Run Length** | 16 | 256 from 32K | RLE compressed, palette indexed |

**VRD Configuration:** Packed Pixel Mode (8bpp, palette indexed)

---

## CRAM (Color Palette RAM)

### Address and Size

- **Base Address**: `$A15200` (68K address space)
- **Size**: 256 entries × 2 bytes = 512 bytes
- **Entry N Address**: `$A15200 + (N × 2)`

### Color Format (RGB555)

Each palette entry is a 16-bit word:

```
Bit:  15   14 13 12 11 10   9  8  7  6  5   4  3  2  1  0
      [ T]  [   Blue   ]  [   Green   ]  [    Red    ]
       │         │              │              │
       │         └─ 5 bits     └─ 5 bits     └─ 5 bits
       └─ Through bit (priority)
```

**Color Components:**
- **Red** (bits 0-4): 5 bits, 32 tones, `$00` (min) to `$1F` (max)
- **Green** (bits 5-9): 5 bits, 32 tones, `$00` (min) to `$1F` (max)
- **Blue** (bits 10-14): 5 bits, 32 tones, `$00` (min) to `$1F` (max)
- **Through bit** (bit 15): Priority/transparency flag

**Total Colors:** 32 × 32 × 32 = 32,768 colors

**Common Colors:**
- `$0000` = Black (R=0, G=0, B=0)
- `$001F` = Red (R=31, G=0, B=0)
- `$03E0` = Green (R=0, G=31, B=0)
- `$7C00` = Blue (R=0, G=0, B=31)
- `$7FFF` = White (R=31, G=31, B=31, Through=0)
- `$FFFF` = White with Through bit (R=31, G=31, B=31, Through=1)

### CRAM Access Control

**PEN Bit (Palette Enable):**
- Located in Frame Buffer Control Register (`$A1518A`)
- **PEN=1**: CRAM accessible
- **PEN=0**: CRAM access waits until PEN=1 (hardware blocks CPU)

**Access Timing:**
- CRAM can be accessed anytime in **Direct Color Mode**
- In **Packed Pixel Mode**, wait for PEN=1 before writing
- Writing when PEN transitions 1→0 results in undefined behavior

**VRD Palette Usage:**
- Palette entries managed by game logic
- Index `$00`: Background (typically black/transparent)
- Index `$FF`: Observed in FPS counter testing (originally undefined in VRD)
- Palette uploads happen during frame setup (VRD fn_200_041 copies palette data)

---

## Frame Buffer Access Protocol (FM Bit)

### FM Bit (VDP Access Authorization)

**Location:** `$A15100` (Adapter Control Register), bit 15 (68K side); `$20004000` (Interrupt Mask Register), bit 15 (SH2 side)

**States:**
- **FM=0**: 68K has VDP access (frame buffer, overwrite images, VDP registers, color palette)
- **FM=1**: SH2 has VDP access (68K reads return undefined, writes ignored)

**Protocol (from VRD fn_200_036-041):**
```asm
; Claim 68K access (byte access to high byte of $A15100)
BCLR    #7,$A15100              ; FM=0 (68K gets VDP access)
                                ; Note: bit 15 of word = bit 7 of high byte

; ... perform frame buffer operations ...

; Return access to SH2
BSET    #7,$A15100              ; FM=1 (SH2 gets VDP access)
```

**Critical Timing Issue:**
- Writing FM=1 from SH2 **immediately preempts** any ongoing 68K VDP access
- Mid-transfer corruption possible if FM switched during active 68K operation
- **Best Practice**: Only switch FM during V-Blank when VDP is idle

**Safe FM State Management:**
```asm
; Save current FM state (byte access to high byte)
BTST    #7,$A15100              ; Test FM bit (bit 15 of word = bit 7 of high byte)
SNE     D0                      ; D0.B = $FF if FM was 1, $00 if 0
BCLR    #7,$A15100              ; FM=0 (claim access)

; ... frame buffer operations ...

; Conditionally restore FM state
TST.B   D0                      ; Was FM originally 1?
BEQ.S   .skip_restore           ; No, leave as 0
BSET    #7,$A15100              ; Yes, restore to 1
.skip_restore:
```

---

## Frame Buffer Double Buffering

### FS Bit (Frame Select)

**Location:** `$A1518B` (Frame Buffer Control Register), bit 0

**Function:** Selects which frame buffer the VDP scans out for display
- **FS=0**: VDP displays FB0 ($840000)
- **FS=1**: VDP displays FB1 ($860000)

**Key Misconception:** FS does NOT remap which buffer is at which address. FB0 is always at `$840000` and FB1 is always at `$860000` from the 68K's perspective. FS only controls which one is **visible on screen**.

**Swap Timing:** Writing the FS bit is always allowed, but the actual swap only takes effect during V-Blank (VBLK=1) or in Blank mode. If written during active display, the swap is deferred to the next V-Blank. After swapping, access the frame buffer only after confirming VBLK=1 or that the FS bit has changed.

**VRD Usage (fn_200_041):**
```asm
BCHG    #0,$A1518B              ; Toggle FS (swap display buffer)
```

### Typical Double Buffer Pattern

```asm
; Frame N: Draw to FB0 while FB1 is displayed
; ... render to $840000 ...

; Swap buffers
BCHG    #0,$A1518B              ; Now FB0 displayed, FB1 becomes draw buffer

; Frame N+1: Draw to FB1 while FB0 is displayed
; ... render to $860000 ...

; Swap buffers
BCHG    #0,$A1518B              ; Now FB1 displayed, FB0 becomes draw buffer
```

---

## Overwrite Area

**Behavior:** When writing `$00` in **byte units** to the frame buffer, the hardware ignores the write (data remains unchanged). This is the "Overwrite Area" behavior.

**Workaround:** Use **word writes** (16-bit MOVE.W) instead of byte writes to ensure `$00` pixels are written correctly. Word writes of `$0000` DO write both zero bytes.

**Example:**
```asm
; BAD - byte write of $00 is ignored
MOVE.B  #$00,(A0)+              ; Pixel unchanged if originally non-zero

; GOOD - word write of $0000 works
MOVE.W  #$0000,(A0)+            ; Both pixels set to palette index 0
```

---

## VRD Frame Buffer Functions

| Function | Address | Purpose |
|----------|---------|---------|
| `vdp_fill_framebuffer` | `$00273C` | Fill entire FB with zeros (screen clear) |
| `vdp_fill_line_table_flat` | `$002714` | Fill line table with constant offset |
| `vdp_fill_line_table_ramp` | `$0026EA` | Fill line table with linear offsets |
| `fn_200_041` | `$001F4A` | Palette transfer + FB swap routine |

**Line Table Initialization (from vdp_fill_line_table_ramp):**
```asm
; Sets up linear 320-pixel-wide scanlines
; Line N offset = $2000 + (N × $100) = $2000 + (N × 256)
; Actual pixel stride is 320, so lines are contiguous in memory
```

---

## Lessons from FPS Counter Implementation Attempts

### What We Confirmed Works

1. ✅ **FM bit control**: BCLR/BSET protocol functions correctly
2. ✅ **CRAM writes**: Setting palette `$FF` to white (`$FFFF`) works
3. ✅ **Frame buffer writes execute**: Visual artifacts prove writes happen
4. ✅ **Word writes**: `MOVE.W #$FFFF,(A1)+` writes two `$FF` palette indices

### Issues Encountered

1. ❌ **Timing problem**: Writes appear in wrong locations (top of screen vs intended line 20)
2. ❌ **Race condition**: SH2 may overwrite 68K FB writes immediately after FM bit restore
3. ❌ **Unknown**: Exact timing window for safe 68K overlay writes unclear

### Recommended Approach for Overlays

Based on testing, direct 68K frame buffer overlays are challenging due to:
- Tight timing windows (SH2 renders continuously)
- FM bit preemption risk
- Unknown safe access patterns

**Alternative:** Use SH2-based overlay rendering via command queue for reliable results.

---

## Hardware Specifications Summary

| Feature | Value |
|---------|-------|
| **Frame Buffers** | 2 × 1 Mbit DRAM (128 KB each) |
| **Resolution** | 320×224 or 320×240 (non-interlace) |
| **Color Palette** | 256 entries × 16-bit RGB555 |
| **Pixel Formats** | 8bpp (packed), 16bpp (direct), 16bpp (RLE) |
| **Line Table** | 256 words × 2 bytes = 512 bytes per FB |
| **Pixel Data** | 320 × 224 = 71,680 bytes (packed pixel mode) |
| **Total FB Size** | ~72 KB per buffer (line table + pixels) |

---

## References

- [32x-hardware-manual.md](../../docs/32x-hardware-manual.md) - Section on Color Palette (lines 1171-1199)
- [32X_REGISTERS.md](32X_REGISTERS.md) - FM bit, FS bit, PEN bit details
- VRD Functions: `fn_200_036` through `fn_200_041` (68K FB access examples)
- FPS Counter Implementation: [fps_render.asm](../../disasm/modules/68k/optimization/fps_render.asm)

---

## See Also

- [DATA_STRUCTURES.md](DATA_STRUCTURES.md) - VRD memory layout and object tables
- [SH2_3D_PIPELINE_ARCHITECTURE.md](../sh2-analysis/SH2_3D_PIPELINE_ARCHITECTURE.md) - SH2 rendering pipeline
- [32X_REGISTERS.md](32X_REGISTERS.md) - Complete 32X register reference
