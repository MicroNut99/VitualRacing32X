# VirtuaRacing32X

Work on Virtua Racing Deluxe (Sega 32X, 1994), rebuilt from source.

**Status: finished.** The last version is V11. It runs on a real Genesis + 32X. No further work will
go into this project.

## What this is

- A fork of [sega-vr-disasm](https://github.com/matiaszanolli/sega-vr-disasm) (MIT) by Matias Zanolli
  and contributors: a disassembly of Virtua Racing Deluxe that rebuilds into a working 4 MB 32X ROM.
  Upstream base: commit `60819ef`.
- The goal here is to improve the game on real 32X hardware: frame rate first, then other changes.

## What this is not

- Not a ROM download, and not the game. **This repo has no Sega code bytes, graphics, sound or track data.**
  You need your own dump of Virtua Racing Deluxe (USA) to build anything.
- Not an official release, and not connected with Sega.

## How it differs from upstream

Upstream keeps the whole original ROM in the repo as `dc.w` lines (`disasm/sections/`, about 57 MB).
Here those lines are taken out:

- `disasm/sections_src/` holds the section files with every run of original ROM words replaced by one line:
  `ROMDATA $start,$end`. Everything hand-written (includes, labels, edited code) is kept as it was.
- `tools/romdata.py expand` puts the ROM words back from your ROM and writes `disasm/sections/`
  (not committed). `make` does this first. The result is the same text as upstream, line for line.
- The hardware and chip manuals upstream copied into `docs/` (Sega, Hitachi, Motorola and others) are left out.
  Get them from upstream if you need them. Links to them in the docs will not work here.
- 8 linker scripts upstream did not commit (`*.lds`) are added, so `make` works from a fresh clone.

The built ROM is byte-identical to an upstream build of the same commit.

## Build

You need: Python 3, GNU make, `xxd`, the SH2 binutils (`sh-elf-as`, `sh-elf-ld`, `sh-elf-objcopy`)
and a Linux-like shell (Linux, WSL, macOS).

1. Put your ROM at `roms/Virtua Racing Deluxe (USA).32x`
   (3,145,728 bytes, MD5 `72b1ad0f949f68da7d0a6339ecd51a3f`; the build checks it).
2. `make all`
3. Output: `build/vr_rebuild.32x` (4 MB). The old ROM is deleted first; if a step fails the build prints
   `*** BUILD FAILED - NO ROM WAS WRITTEN ***` and leaves no ROM.

Tested in PicoDrive, Fusion 3.64 and on a real Genesis + 32X (V9). V3-V8 hung on real hardware after the logo (fixed in V9).

## Fixes to upstream

- **V7: car select and menu fades back to full speed.** Upstream's single-shot command $22 and its
  async command $27 put their data in the same COMM registers at the same time; the car select drew a
  new picture only every 6-7 frames and the stripe fades between menus took about 4 times longer.
  Both senders and the jump table entry are back to the original game code. See KNOWN_ISSUES.md.

- **V8: the game plays exactly like the original again.** Every byte upstream changed in the original
  game area was checked against the original ROM. Fixed:
  - 10 calls in the race code (`race_frame_update`, `race_state_read_sound_trigger`,
    `scene_dispatch_input_replay`) went to the wrong function or into a data table after
    upstream renamed functions; they call the original targets again.
  - `speed_interpolation`: upstream's "divide by 103" shortcut was 1.2% off; the exact divide is back.
  - `depth_sort`: upstream's faster sort dropped the tie-break the race positions use; original back.
  - 2-player races showed a black screen (upstream's 40 FPS camera); original back, menu switch removed.
  - 2-player races drew player 2's view wrong (upstream's S-6 Phase B SH2 transform); original back.
  - Command $25 is back to the original handshake, like $22 and $27 in V7.
  Tested in PicoDrive with the same pad input as the original ROM: attract demo (6,000 frames),
  1-player race (4,000 frames) and 2-player race (2,300 frames) are pixel-identical to the original.
  Upstream changes that still differ give identical pictures: the S-1 sprite update, S-6 Phase A
  vertex transform, the STOP in `wait_for_vblank`, the Slave idle check.

- **V9: real hardware.** V3-V8 hung on a real 32X right after the Sega Sports logo: the pause
  menu code read a 32X video register without first taking it from the SH2s. Fixed; see
  KNOWN_ISSUES.md.

## Pause menu (V3-V11)

Start during a 1-player race opens the menu (2-player races keep the game's own pause).
The 32X picture is switched off while the menu is up, so the menu is always readable.

| Line | Does |
|---|---|
| CONTINUE | back to the race (the game's own unpause) |
| RETRY COURSE | back to the course select with the same car and course; Start races again |
| QUIT RACE | the game's own quit (A+B+C): to the result screen |
| TIMING | on: the numbers below are also shown live during the race, bottom middle, in the black strip under the 3D view. They are drawn into both 32X frame buffers once a second (the 68000 takes the frame buffer for a moment after the SH2 finished its frame). Since V10 only the characters that changed are drawn: no lost frames (FPS 20, LAG 0 with the line on) |
| `FPS 20 68K 48% SH2 52% LAG 0` | the last second before pausing: frames shown per second (32X frame-buffer swaps), 68000 busy time, how far into the 3-frame window (from one swap to the next) the SH2 reports its frame done (worst of the second; COMM1_LO bit 0, timed by the 68000 waiting in work RAM while the line is on), frames where the 68000 was still busy at vblank |
| `VR32X V11 10-13 23:31` | version and build time (month-day hour:minute, Pacific), written by the Makefile, so a screenshot shows which build ran |

Up/Down choose, A, C or Start select, Left/Right also switch ON/OFF.

The SH2's "frame done" bit (COMM1_LO bit 0) is read until two reads agree before the 68000 takes
the frame buffer (V6): the SH2 can be writing that register at the moment it is read.

The SH2s' busy time is not shown: the 68000 cannot read the SH2 memory, and the COMM registers
are all in use.

Code: `disasm/modules/68k/optimization/pause_menu.asm` (in the free ROM at `$01C2DC`), hooked in at
the main loop (`vdp_display_init.asm`), the V-INT handler (`code_200.asm`), the pause sub-state table
(`state_disp_ctrl_poll_sprite_update.asm`) and `state4_epilogue` (`code_2200.asm`), each marked `VR32X`.

## Where the time goes (from upstream's profiling)

| CPU | Busy | Job |
|---|---|---|
| 68000 | about 48% | game logic |
| Master SH2 | 0-36% | commands, block copies |
| Slave SH2 | about 73% | all 3D drawing (the bottleneck) |

The game logic runs at 20 frames per second; upstream shows 40 by camera interpolation.
See `CLAUDE.md`, `BACKLOG.md` and `OPTIMIZATION_PLAN.md` for the details upstream wrote down.

## Credits

- **MicroNut99** - this fork
- **Sega** - Virtua Racing Deluxe
- **Matias Zanolli and the sega-vr-disasm contributors** - the disassembly, tools and documentation (MIT)
- **vasm** (Volker Barthelmann, Frank Wille) - the 68000 assembler in `tools/`
- **notaz** - PicoDrive, used for testing
- Code written with help from Claude (Anthropic)

Virtua Racing is a trademark of Sega. This project is not affiliated with Sega.
