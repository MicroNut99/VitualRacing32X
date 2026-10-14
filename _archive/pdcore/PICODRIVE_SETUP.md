# PicoDrive Integration Setup

This guide explains how to build pdcore integrated with PicoDrive for real hardware debugging.

## Prerequisites

- GCC toolchain
- Git
- Make

## Step 1: Clone PicoDrive

```bash
mkdir -p third_party
cd third_party
git clone https://github.com/irixxxx/picodrive.git
cd picodrive
git submodule update --init
```

## Step 2: Apply Debug Hooks

Apply the pdcore debug hooks patch:

```bash
cd third_party/picodrive
patch -p1 < ../../pdcore/patches/picodrive-debug-hooks.patch
```

Or manually apply changes (24 lines total):

### cpu/sh2/sh2.h
Add to SH2 struct before closing brace:
```c
// Debug hooks (pdcore debugger support - NULL when no debugger attached)
int (*debug_check_breakpoint)(struct SH2_ *sh2);
void *debug_context;
```

### cpu/sh2/mame/sh2pico.c
Add in sh2_execute_interpreter() main loop, after IRQ check:
```c
// Debug hook: check for breakpoints (pdcore debugger support)
if (sh2->debug_check_breakpoint && sh2->debug_check_breakpoint(sh2)) {
    break;  // Breakpoint hit - stop execution
}
```

### pico/pico_int.h
Add to Pico32x struct:
```c
// Debug hooks (pdcore debugger support - NULL when no debugger attached)
void (*debug_vblank_callback)(void);
```

### pico/32x/32x.c
Add in p32x_start_blank() after V-BLANK interrupt trigger:
```c
// Debug hook: V-BLANK callback (pdcore debugger support)
if (Pico32x.debug_vblank_callback) {
  Pico32x.debug_vblank_callback();
}
```

## Step 3: Copy Bridge File

```bash
cp pdcore/patches/pdcore_bridge.c third_party/picodrive/pico/
```

## Step 4: Build PicoDrive with pdcore

```bash
cd third_party/picodrive
./configure
USE_PDCORE=1 make -j$(nproc)
```

## Step 5: Test

```bash
# Run PicoDrive with a 32X ROM
./picodrive ../../roms/game.32x
```

## Building the Integrated Library

For standalone pdcore testing with PicoDrive headers:

```bash
cd pdcore
make -f Makefile.integrated
```

## Debug Hook Design

The integration uses a minimal "handler-pointer" pattern (inspired by BlastEm):

1. **SH2 Breakpoint Hook**: Function pointer checked in execution loop
2. **V-BLANK Hook**: Callback on every V-BLANK for frame-perfect debugging

These hooks are NULL by default and have zero overhead when no debugger is attached.
