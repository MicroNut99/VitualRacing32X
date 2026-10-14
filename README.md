# VirtuaRacing32X

Work on Virtua Racing Deluxe (Sega 32X, 1994), rebuilt from source.

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

Tested in PicoDrive. Fusion and real hardware: not yet.

## Pause menu (V3-V6)

Start during a 1-player race opens the menu (2-player races keep the game's own pause).
The 32X picture is switched off while the menu is up, so the menu is always readable.

| Line | Does |
|---|---|
| CONTINUE | back to the race (the game's own unpause) |
| RETRY COURSE | back to the course select with the same car and course; Start races again |
| QUIT RACE | the game's own quit (A+B+C): to the result screen |
| 2P 40 FPS CAM | upstream's camera interpolation on/off. It only runs in 2-player races (dispatcher `$005020`); the 1-player race is 20 fps either way (see KNOWN_ISSUES.md) |
| TIMING | on: the numbers below are also shown live during the race, bottom middle, in the black strip under the 3D view. They are drawn into both 32X frame buffers once a second (the 68000 takes the frame buffer for a moment after the SH2 finished its frame), which costs about 1 lag frame a second |
| `FPS 20 68K 48% LAG 0` | the last second before pausing: frames shown per second (32X frame-buffer swaps), 68000 busy time, frames where the 68000 was still busy at vblank |
| `VR32X V6 10-13 21:19` | version and build time (month-day hour:minute, Pacific), written by the Makefile, so a screenshot shows which build ran |

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
