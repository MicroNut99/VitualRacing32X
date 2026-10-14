# 68K PC-Level Profiling for VRD

**Purpose:** Identify where the 68K CPU spends its time to find optimization targets
**Status:** Working — profiler verified, results analyzed (March 2026)
**Related:** [68K_BOTTLENECK_ANALYSIS.md](../../analysis/profiling/68K_BOTTLENECK_ANALYSIS.md)

## Quick Start

```bash
# 1. Build PicoDrive with profiling support (from repo root)
cd third_party/picodrive
make -f Makefile.libretro platform=unix -j$(nproc)
cp picodrive_libretro.so ../../tools/libretro-profiling/

# 2. Build ROM
cd ../..
make clean && make all

# 3. Run profiling (2400 frames = 40 seconds)
cd tools/libretro-profiling
VRD_PROFILE_PC=1 \
VRD_PROFILE_PC_LOG=vrd_profile_pc.csv \
./profiling_frontend ../../build/vr_rebuild.32x 2400 --autoplay

# 4. Analyze results (auto-resolves function names from FUNCTION_QUICK_LOOKUP.md)
python3 analyze_pc_profile.py vrd_profile_pc.csv 30
```

## What This Measures

### Frame-Level (Already Working)
- **68K**: 127,987 cycles/frame @ 7.67 MHz (100.1% utilization)
- **Master SH2**: 139,568 cycles/frame @ 23 MHz (36.4% utilization)
- **Slave SH2**: 299,958 cycles/frame @ 23 MHz (78.3% utilization)

### PC-Level (Verified March 2026)
- **68K hotspots**: Which PCs consume the most cycles (200 unique PCs captured)
- **Function-level aggregation**: Groups scattered PCs by containing function
- **Auto name resolution**: Maps PCs to function names via `FUNCTION_QUICK_LOOKUP.md`
- **Per-function breakdown**: Actionable optimization targets

## Profiling Results (March 2026, 2400 frames)

### Function-Level Top 10

| Rank | Function | Share | PCs | Notes |
|------|----------|-------|-----|-------|
| 1 | **WRAM_code** (BIOS COMM polling) | **49.4%** | 2 | BIOS adapter loops in Work RAM |
| 2 | **SH2 Cmd 27 Sprite Render** | **11.0%** | 2 | Sprite render command submission |
| 3 | Menu Tile Copy to VDP | 2.4% | 5 | Menu-only, irrelevant during racing |
| 4 | Angle Normalization | 2.3% | 24 | Math, spread across many PCs |
| 5 | depth_sort | 2.1% | 11 | Sorting (optimized via QW-4a) |
| 6 | Physics Integration | 1.9% | 15 | Physics engine |
| 7 | AI Opponent Select | 1.3% | 17 | AI logic |
| 8 | sine_cosine_quadrant_lookup | 1.0% | 9 | Trig lookup |
| 9 | rotational_offset_calc | 1.0% | 9 | Rotation math |
| 10 | race_entity_update_loop | 0.7% | 11 | Entity update loop |

**Top 10 functions = 73.1% of all 68K cycles.**

### Key Finding (revised March 8, 2026)

**49.4% of 68K time is V-blank synchronization, NOT COMM polling.** The WRAM code at $FF0010/$FF0014 is the BIOS adapter's main loop, which polls `VINT_STATE` ($FFFFC87A) waiting for V-blank between frame iterations. WRAM caller tracking confirmed: top callers are state dispatchers and frame orchestrators, not COMM command functions.

The BIOS adapter main loop at $FF0000:
```
JSR $884CBC          ; Call game's per-frame state dispatcher
MOVE.W #$0054,VINT_STATE.w  ; Request V-blank sync
MOVE #$2300,SR       ; Enable interrupts
TST.W VINT_STATE.w   ; ← 43.5% hotspot (V-blank poll)
Bcc .poll            ; ← 5.8% hotspot (loop back)
BRA.S MainLoop       ; Next frame
```

**Implication:** The V-blank wait is a symptom, not the cause. The game takes ~3 TV frames per game frame at 20 FPS. Reducing useful work means fewer TV frames = higher FPS. The actual useful work breakdown (excluding V-blank wait):

| Function | % of Useful Work |
|----------|-----------------|
| SH2 Cmd 27 (COMM7 wait) | 21.7% |
| Angle Normalization | 4.5% |
| depth_sort | 4.2% |
| Physics Integration | 3.8% |
| Other (AI, trig, etc.) | ~66% |

**Saving 33% of useful work → 2 TV frames/game frame → 30 FPS (+50%).**

## Implementation Details

### Profiling Method
- **68K**: FAME sub-batch sampling — runs 68K in 32-cycle chunks, samples PC after each chunk
- **SH2**: Not currently profiled at PC level (SH2 cycle counting bug produces counts, not cycle weights)
- **Output**: Histogram of PC → (total_cycles, count, avg_cycles, share%) — top 200 entries exported

### Sampling Granularity
```
68K: 127,987 cycles/frame ÷ 32-cycle chunks ≈ 4,000 samples/frame
@ 2400 frames ≈ 9.6M total samples → 200 unique PCs in top histogram
```

32-cycle granularity provides instruction-level hotspot identification.

### Performance Impact
- **Overhead**: ~10-15% slowdown (FAME sub-batch execution)
- **Memory**: ~1.5MB for 3 hash tables (65536 entries × 3 CPUs)
- **Disk**: ~15KB CSV output (top 200 entries)

## File Structure

### Source Modifications (in third_party/picodrive/)
- `platform/libretro/libretro.c` — Hash table histogram, env var init, CSV export
- `pico/pico_cmn.c` — FAME 32-cycle sub-batch sampling in SekExecM68k()
- `pico/32x/32x.c` — SH2 work cycle counters

### Analysis Tools
- `analyze_profile.py` — Frame-level analysis (68K/MSH2/SSH2 cycles per frame)
- `analyze_pc_profile.py` — PC-level hotspot analysis with function name resolution

### Output Files
- `vrd_profile_pc.csv` — PC hotspots (cpu, pc, total_cycles, count, avg, share)
- `vrd_profile_frames.csv` — Frame-level cycles (frame, m68k_cycles, msh2_cycles, ssh2_cycles)
- `68k_hotspots.txt` — Top 20 68K hotspots with function names (auto-generated)

## Usage

### Basic Analysis (Top 20 hotspots + function aggregation)
```bash
python3 analyze_pc_profile.py vrd_profile_pc.csv
```

### Extended Analysis (Top 50)
```bash
python3 analyze_pc_profile.py vrd_profile_pc.csv 50
```

### Output Sections
1. **Per-PC hotspots** — Individual instruction addresses with function names, cumulative share
2. **Function-level aggregation** — Groups all PCs from the same function, shows true function cost
3. **Analysis summary** — Concentration metrics (top 10/20 PC share)
4. **Exported hotspot file** — `68k_hotspots.txt` for cross-referencing with disassembly

## Interpreting Results

### Function-Level Aggregation is Key

Individual PCs are scattered across functions. The **function-level aggregation** section groups them, revealing true costs. For example, `depth_sort` appears at 11 different PCs totaling 2.1% — no single PC exceeds 0.42%.

### Blocking vs Work

**Blocking indicators** (WRAM_code):
- BIOS adapter polling loops copied to Work RAM ($FF0000+)
- 49.4% of all cycles — confirms architectural bottleneck
- Cannot be optimized in 68K code — requires reducing SH2 response time

**Command submission** (SH2 Cmd 27):
- 11.0% of cycles — the sprite render command path
- Includes COMM register handshake waits

**Computation** (everything else):
- ~40% spread across game logic, physics, math, AI
- Individual functions rarely exceed 2%
- Offload candidates for idle Master SH2

### Address Mapping

- **$FF0000+** → WRAM (BIOS adapter code)
- **$880000+** → 32X ROM (file offset = pc - $880000)
- Function names resolved via `analysis/FUNCTION_QUICK_LOOKUP.md`

## Troubleshooting

### Build Issues

**PicoDrive must be built from clean upstream** (origin/master). Local SH2 boot patches broke 32X emulation — the 68K gets stuck in the adapter init spin loop and Master SH2 stays at 0 cycles. If profiling shows 99%+ in `$FF0010`/`$FF0014` and 0 Master SH2 cycles, check for local PicoDrive commits.

```bash
cd third_party/picodrive
git log --oneline -5  # Should show upstream commits only
```

### No PC Samples Collected
- Verify `VRD_PROFILE_PC=1` env var is set
- Verify `VRD_PROFILE_PC_LOG` points to a writable path
- Check that `picodrive_libretro.so` has profiling compiled in (grep for `vrd_profile_pc_sample`)

### FAME vs Musashi
The default x86_64 build uses **FAME** (EMU_F68K) which supports sub-batch sampling. Musashi builds produce per-instruction count=1 entries — not useful for cycle profiling. Stick with the default FAME build.

### Known Limitation: SH2 PC Profiling
SH2 per-instruction cycle counting has a bug (`cycles_this_inst` always = 0, falls back to 1 cycle/instruction). SH2 PC data shows instruction counts, not cycle weights. Not needed for current work since the 68K is the bottleneck.

## Optimization Priorities (from profiling data)

### Confirmed: Blocking > 50%

**60.4% of 68K cycles** are in COMM polling (49.4%) + command submission (11.0%). This confirms the architectural bottleneck: reducing SH2 response latency is the highest-impact optimization.

### Computation Offload Candidates

The remaining ~40% is spread across many functions, none exceeding 2.3%. Best candidates for offloading to the idle Master SH2:

| Function | Share | Why |
|----------|-------|-----|
| Angle Normalization | 2.3% | Pure math, no side effects |
| Physics Integration | 1.9% | Deterministic computation |
| sine_cosine_quadrant_lookup | 1.0% | Table lookup, easily parallelized |
| rotational_offset_calc | 1.0% | Pure math |

See [OPTIMIZATION_PLAN.md](../../OPTIMIZATION_PLAN.md) Track 4 for offload strategy.

## Related Documentation

- [68K_BOTTLENECK_ANALYSIS.md](../../analysis/profiling/68K_BOTTLENECK_ANALYSIS.md) — Ground truth: 68K at 100%
- [ARCHITECTURAL_BOTTLENECK_ANALYSIS.md](../../analysis/ARCHITECTURAL_BOTTLENECK_ANALYSIS.md) — Blocking sync model
- [OPTIMIZATION_PLAN.md](../../OPTIMIZATION_PLAN.md) — Strategic roadmap
- [FUNCTION_QUICK_LOOKUP.md](../../analysis/FUNCTION_QUICK_LOOKUP.md) — Function name lookup (used by analyzer)
