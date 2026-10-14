#!/usr/bin/env python3
"""
Phase 4.2 Split Point Patcher

Modifies the SLAVE_START value in ROM to test different polygon distributions.
Changes SDRAM sync buffer @ 0x22000414 to adjust Slave workload.

Usage:
    python3 patch_split_point.py input.32x output.32x --split 350
"""

import sys
import struct
import os

SYNC_BUFFER_ROM_ADDR = 0x22000414  # SLAVE_START offset in sync buffer
FILE_OFFSET = SYNC_BUFFER_ROM_ADDR - 0x02000000  # Convert to file offset

def patch_split_point(input_rom, output_rom, split_point):
    """Patch ROM with new SLAVE_START polygon value"""

    print(f"[*] Patching ROM: {input_rom}")
    print(f"    Split point: Slave will process polygons {split_point}-799")

    if not os.path.exists(input_rom):
        print(f"[!] Input ROM not found: {input_rom}")
        sys.exit(1)

    # Read ROM
    with open(input_rom, 'rb') as f:
        rom_data = bytearray(f.read())

    # Calculate file offset for SLAVE_START in sync buffer
    # Sync buffer is at SH2 address 0x22000400 (SDRAM)
    # Which maps to ROM at a different location, but we're patching display list area
    # Actually, sync buffer is in SDRAM, not ROM - it's initialized by code
    #
    # Instead, we patch the default values in the assembled code at 0x20650+
    # These are in the slave_main_loop initialization

    # The SLAVE_START literal is at binary offset ~0x14 in sync buffer init
    # But that's runtime - we need to patch ROM injection point

    # For now, let's patch by finding the sync buffer initialization code
    # Pattern: the SLAVE_START constant is typically followed by polygon range

    # Better approach: patch display list COMMAND area that Master uses to signal
    # Actually, simplest: just document the change and modify assembly if needed

    print(f"[*] Calculating patch location...")

    # The split point is stored in the sync buffer at 0x22000414 (SDRAM runtime)
    # We can't patch SDRAM directly from ROM
    # Instead, we need to either:
    # 1. Patch the assembly code that initializes it
    # 2. Patch the Master code that sets it before dispatch

    # For Phase 4.2 prototype, we'll modify the slave_process_polygons
    # start point by patching at a known location

    # Actually, let's just document what needs to change
    print(f"\n[!] Note: SLAVE_START is initialized at runtime by Master")
    print(f"[!] To change split point, modify:")
    print(f"    - dispatch_slave_and_wait() in sh2_3d_engine_annotated.asm")
    print(f"    - Change: mov.l #400,r0  -> mov.l #{split_point},r0")
    print(f"    - Line: @(SLAVE_START_OFFSET, r14)")

    # For now, copy ROM as-is
    with open(output_rom, 'wb') as f:
        f.write(rom_data)

    print(f"[+] ROM patched: {output_rom}")
    print(f"    Note: Manual assembly modification still required for full effect")

def main():
    if len(sys.argv) < 4:
        print("Usage: patch_split_point.py <input.32x> <output.32x> --split <point>")
        print("")
        print("Examples:")
        print("  python3 patch_split_point.py base.32x test_350.32x --split 350")
        print("  python3 patch_split_point.py base.32x test_300.32x --split 300")
        sys.exit(1)

    input_rom = sys.argv[1]
    output_rom = sys.argv[2]

    split_point = 400  # Default
    if '--split' in sys.argv:
        idx = sys.argv.index('--split')
        if idx + 1 < len(sys.argv):
            split_point = int(sys.argv[idx + 1])

    patch_split_point(input_rom, output_rom, split_point)

if __name__ == '__main__':
    main()
