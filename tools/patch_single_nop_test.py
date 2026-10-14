#!/usr/bin/env python3
"""
ULTRA-MINIMAL TEST: Change a single NOP instruction

This verifies the patching mechanism itself works. If this crashes,
the game has ROM integrity checking or our patching approach is fundamentally broken.
"""

import sys
from pathlib import Path

def main():
    print("=" * 70)
    print(" Virtua Racing - SINGLE NOP TEST")
    print(" Changes: 1 byte (00 → 00, literally nothing)")
    print("=" * 70)

    input_file = Path("Virtua Racing Deluxe (USA).32x")
    output_file = Path("Virtua Racing - SINGLE-NOP-TEST.32x")

    if not input_file.exists():
        print(f"\n❌ Input ROM not found: {input_file}")
        sys.exit(1)

    print(f"\n✓ Reading ROM: {input_file}")
    rom_data = bytearray(input_file.read_bytes())

    # Find a safe NOP in func_065 and... keep it as NOP
    # Actually, let's change ONE instruction in the middle to a different NOP
    # Original func has many "31 DC" (ADD R13,R1) instructions
    # Let's change the FIRST ONE (at offset 0x23F3E) to "00 09" (NOP)
    # This will break functionality but test if ANY change is tolerated

    test_location = 0x23F3E  # First ADD R13,R1 in loop
    original_bytes = bytes(rom_data[test_location:test_location+2])

    print(f"\n✓ Original bytes at 0x{test_location:06X}: {original_bytes.hex()}")
    print(f"  Instruction: ADD R13,R1")

    # Replace with NOP
    rom_data[test_location:test_location+2] = bytes([0x00, 0x09])

    print(f"  New bytes: 00 09 (NOP)")
    print(f"\n✓ This will break func_065 (wrong address calc)")
    print(f"  But if it RUNS AT ALL, patching works!")

    # Save
    output_file.write_bytes(rom_data)
    print(f"\n✓ Saved: {output_file}")
    print("\nExpected behavior:")
    print("  - If boots with graphics glitches: Patching works! ✓")
    print("  - If crashes on boot: ROM has integrity check ✗")

if __name__ == '__main__':
    main()
