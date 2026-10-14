#!/usr/bin/env python3
"""
ABSOLUTE MINIMAL TEST: Replace first ADD R13,R1 with two NOPs

This changes ONLY 2 bytes in the middle of func_065.
If this crashes, ANY modification to func_065 is problematic.
"""

import sys
from pathlib import Path

def main():
    print("=" * 70)
    print(" Virtua Racing - ABSOLUTE MINIMAL NOP TEST")
    print(" Changes: 2 bytes (ADD R13,R1 → NOP; NOP)")
    print("=" * 70)

    input_file = Path("Virtua Racing Deluxe (USA).32x")
    output_file = Path("Virtua Racing - MINIMAL-NOP.32x")

    if not input_file.exists():
        print(f"\n❌ Input ROM not found: {input_file}")
        sys.exit(1)

    print(f"\n✓ Reading ROM: {input_file}")
    rom_data = bytearray(input_file.read_bytes())

    # First ADD R13,R1 is at 0x23F3E (end of first iteration)
    # Original: 31 DC
    # Replace with: 00 09 (NOP)

    nop_location = 0x23F3E
    original = rom_data[nop_location:nop_location+2]

    print(f"\n✓ Location: 0x{nop_location:06X}")
    print(f"  Original: {original.hex()} (ADD R13,R1)")
    print(f"  New:      0009 (NOP)")

    rom_data[nop_location] = 0x00
    rom_data[nop_location+1] = 0x09

    # Save
    output_file.write_bytes(rom_data)
    print(f"\n✓ Saved: {output_file}")
    print("\nExpected behavior:")
    print("  - If boots with glitches: Modification tolerated ✓")
    print("  - If crashes: func_065 cannot be modified at all ✗")
    print("\nThis will cause graphics corruption (wrong address calc)")
    print("but should NOT crash if modification is allowed.")

if __name__ == '__main__':
    main()
