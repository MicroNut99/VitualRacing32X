# VRD Baseline Profiling Comparison

**Date:** 2026-01-26  
**Tool:** libretro PicoDrive with cycle instrumentation  
**Duration:** 2400 frames (40 seconds) with autoplay

---

## Results Summary

### Original ROM (3MB)
- **ROM:** `roms/Virtua Racing Deluxe (USA).32x` (3,145,728 bytes)
- **Master SH2:** 139,567.6 cycles/frame (36.4% utilization)
- **Slave SH2:** 299,958.4 cycles/frame (78.3% utilization)
- **Work Distribution:** Master 31.8%, Slave 68.2%
- **3-Frame Pattern:** Frames 0/1/2 = 40,163 / 189,420 / 189,244 cycles

### v4.0 Rebuild ROM (4MB)
- **ROM:** `build/vr_rebuild.32x` (4,194,304 bytes)
- **Master SH2:** 139,567.6 cycles/frame (36.4% utilization)
- **Slave SH2:** 299,958.4 cycles/frame (78.3% utilization)
- **Work Distribution:** Master 31.8%, Slave 68.2%
- **3-Frame Pattern:** Frames 0/1/2 = 40,163 / 189,420 / 189,244 cycles

---

## Validation Status

✅ **IDENTICAL BEHAVIOR** - v4.0 rebuild matches original ROM exactly
- Same cycle counts per frame
- Same work distribution
- Same 3-frame rendering pattern
- Same CPU utilization

**Conclusion:** v4.0 rebuild with reverted hooks produces functionally identical execution to the original ROM.

---

## Baseline Characteristics

### Work Distribution
- **Slave dominance:** Slave does 115% MORE work than Master
- **Master low frames:** Every 3rd frame, Master drops to ~4% utilization (40K cycles)
- **Master high frames:** Frames 1-2 in cycle, Master runs at ~49% utilization (189K cycles)
- **Slave consistent:** Slave maintains ~78% utilization across all frames

### 3-Frame Rendering Cycle
VRD uses a 3-frame rendering pattern where Master alternates between:
1. **Frame 0 (Low):** 40,163 cycles - Master mostly idle, Slave does rendering
2. **Frame 1 (High):** 189,420 cycles - Master active, balanced workload
3. **Frame 2 (High):** 189,244 cycles - Master active, balanced workload

This pattern repeats throughout gameplay.

### Cycle Budget Analysis
- **Total available:** 383,333 cycles/frame @ 23MHz, 60fps
- **Master average:** 139,568 cycles (36.4% of budget)
- **Slave average:** 299,958 cycles (78.3% of budget)
- **Peak cycles:** 306,670 cycles (Slave worst case, 80% of budget)
- **Headroom:** ~76K cycles/frame (~20%) available for optimization

---

## Next Steps

1. ✅ **Baseline established** - Original and rebuild behavior validated
2. **Shadow path activation** - Enable instrumentation without changing rendering
3. **Timing validation** - Measure Slave execution time for func_021_optimized
4. **Live activation** - Enable true parallel processing if timing validates

---

## Data Files

- **Original ROM:** `/tmp/vrd_profile_original.csv` (2398 frames)
- **v4.0 Rebuild:** `/tmp/vrd_profile_v40_rebuild.csv` (2398 frames)

