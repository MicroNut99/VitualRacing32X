# 68K PC-Level Profiling Implementation Plan

**Status:** Patch created, needs 68K sampling hooks
**Goal:** Capture 68K PC hotspots to identify blocking wait functions

## Current State

✅ **SH2 PC profiling working** - Successfully identified 66.6% Slave bottleneck
✅ **Frame-level 68K profiling working** - Confirmed 68K at 100% utilization
❌ **68K PC-level profiling missing** - This is the gap we're filling

## Implementation Approach

### Option 1: Instruction-Level Sampling (Most Accurate)

Hook into the 68K interpreter's instruction execution loop to sample PC after each instruction.

**Pros:**
- Cycle-accurate profiling
- Captures every executed instruction
- Matches SH2 profiling methodology

**Cons:**
- Requires modifying 68K core (Musashi/Cyclone/FAME)
- Performance impact (10-20% slowdown)
- Core-specific implementation

**Implementation:**
```c
/* In cpu/musashi/m68kops.c or cpu/cyclone/Cyclone.c */
void m68k_execute_instruction() {
    unsigned int pc_before = m68k_get_pc();
    int cycles_before = m68k_get_cycles();

    /* Execute instruction */
    m68k_execute_one();

    int cycles_after = m68k_get_cycles();
    int cycles_consumed = cycles_before - cycles_after;

    /* Sample PC */
    if (vrd_profile_pc_enabled) {
        vrd_profile_pc_sample(0, pc_before, cycles_consumed);
    }
}
```

### Option 2: Periodic Sampling (Statistical)

Sample 68K PC periodically (every N cycles or per frame) instead of every instruction.

**Pros:**
- Lower performance impact (<5% slowdown)
- Core-agnostic (works with any 68K emulator)
- Good enough for hotspot identification

**Cons:**
- Statistical, not cycle-accurate
- Might miss short-lived functions
- Sampling frequency tradeoff (accuracy vs performance)

**Implementation:**
```c
/* In platform/libretro/libretro.c - called from PicoFrame() */
static int vrd_68k_sample_counter = 0;
#define VRD_68K_SAMPLE_INTERVAL 100  /* Sample every 100 cycles */

void retro_run(void) {
    /* ... existing frame code ... */

    /* Sample 68K PC periodically during frame */
    if (vrd_profile_pc_enabled && vrd_is_32x) {
        vrd_68k_sample_counter += m68k_cycles_this_frame;

        while (vrd_68k_sample_counter >= VRD_68K_SAMPLE_INTERVAL) {
            unsigned int pc = SekPc;  /* Get current 68K PC */
            vrd_profile_pc_sample(0, pc, VRD_68K_SAMPLE_INTERVAL);
            vrd_68k_sample_counter -= VRD_68K_SAMPLE_INTERVAL;
        }
    }
}
```

### Option 3: Hybrid Approach (Recommended)

Use periodic sampling with adaptive frequency based on frame time.

**Pros:**
- Balance of accuracy and performance
- Captures enough samples for meaningful data
- Minimal slowdown

**Implementation:**
- Sample every 1000 cycles (~130 samples per frame)
- At 127,987 cycles/frame, this gives 127-128 samples
- Enough granularity to identify blocking loops

## Patch Status

The `libretro_vrd_profiling_v3_pc.patch` includes:
- ✅ Frame-level profiling (68K + SH2)
- ✅ SH2 PC-level sampling infrastructure
- ✅ PC histogram accumulation and export
- ❌ 68K PC sampling hooks (needs Option 2 or 3 added)

## Next Steps

1. **Add 68K sampling** - Implement Option 3 (hybrid periodic sampling)
2. **Test build** - Run `./build_with_68k_profiling.sh`
3. **Profile ROM** - Run with `VRD_PROFILE_PC=1 VRD_PROFILE_PC_LOG=pc.csv`
4. **Analyze results** - Run `analyze_pc_profile.py pc.csv`

## Expected Output

**68K PC hotspots we're looking for:**
```
CPU,PC,Total_Cycles,Count,Avg_Cycles,Share
68K,0x00E316,45000000,50000,900,35.2%   ← sh2_send_cmd_wait
68K,0x00E342,30000000,50000,600,23.4%   ← sh2_wait_response
68K,0x00E22C,15000000,14000,1071,11.7%  ← sh2_graphics_cmd
68K,0x002890,8000000,20000,400,6.3%     ← sh2_comm_sync
...
```

This will answer:
- What % of 68K time is spent in blocking waits?
- Which specific PCs are the polling loops?
- How much time per function call?

## Implementation Priority

**High:** Option 3 (periodic sampling with 1000-cycle interval)
**Medium:** Option 2 (simple periodic sampling)
**Low:** Option 1 (instruction-level - overkill for our needs)

**Recommended:** Start with Option 3, validate with known addresses from [68K_BOTTLENECK_ANALYSIS.md](../../analysis/profiling/68K_BOTTLENECK_ANALYSIS.md)

---

**Status:** Ready for 68K sampling implementation
**Blocker:** Need to add periodic sampling hooks to patch
**ETA:** 1-2 hours for implementation + testing
