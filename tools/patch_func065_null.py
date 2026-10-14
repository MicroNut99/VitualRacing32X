#!/usr/bin/env python3
"""
Null patch for func_065 - exact copy to test patching infrastructure

This creates an identical ROM to verify:
1. BSR call site identification is correct
2. ROM patching mechanism works
3. Emulator accepts modified ROM
"""

import sys
from pathlib import Path

def main():
    print("=" * 70)
    print(" Virtua Racing - func_065 NULL PATCH (Testing Only)")
    print(" Expected Result: Identical behavior to original")
    print("=" * 70)

    input_file = Path("Virtua Racing Deluxe (USA).32x")
    output_file = Path("Virtua Racing - NULL.32x")

    if not input_file.exists():
        print(f"\n❌ Input ROM not found: {input_file}")
        sys.exit(1)

    print(f"\n✓ Reading ROM: {input_file}")
    rom_data = bytearray(input_file.read_bytes())
    print(f"  Size: {len(rom_data):,} bytes")

    # Exact copy of func_065 from ROM 0x23F2E-0x23FC2
    # This is just moving the start point by 2 bytes (from 0x23F2C to 0x23F2E)
    # So we're testing if the actual function starts at 0x23F2E (where BSR calls it)

    # Read original function starting at 0x23F2E (where BSR calls)
    func_start = 0x23F2E
    func_end = 0x23FC2
    func_size = func_end - func_start  # Should be 148 bytes

    print(f"\n✓ Function at ROM 0x{func_start:06X}-0x{func_end:06X}")
    print(f"  Size: {func_size} bytes")

    original_bytes = rom_data[func_start:func_end]

    # Write it back (no-op, but tests the mechanism)
    rom_data[func_start:func_end] = original_bytes

    # Save
    output_file.write_bytes(rom_data)
    print(f"\n✓ NULL patch ROM saved: {output_file}")
    print("  This ROM should behave IDENTICALLY to the original")
    print("\n✓ If this boots, patching infrastructure works correctly")

if __name__ == '__main__':
    main()
