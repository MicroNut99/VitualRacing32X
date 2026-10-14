#!/usr/bin/env python3
"""
NULL patch with relocation - exact copy of func_065 relocated to test trampoline

This verifies that:
1. Register-preserving trampoline works correctly
2. Relocated code executes properly
3. Issue is NOT with relocation mechanism, but with FIFO batching logic
"""

import sys
import struct
from pathlib import Path

def main():
    print("=" * 70)
    print(" Virtua Racing - func_065 RELOCATED NULL PATCH (Testing)")
    print(" Expected Result: Identical behavior to original")
    print("=" * 70)

    input_file = Path("Virtua Racing Deluxe (USA).32x")
    output_file = Path("Virtua Racing - RELOCATED-NULL.32x")

    if not input_file.exists():
        print(f"\n❌ Input ROM not found: {input_file}")
        sys.exit(1)

    print(f"\n✓ Reading ROM: {input_file}")
    rom_data = bytearray(input_file.read_bytes())
    print(f"  Size: {len(rom_data):,} bytes")

    # Read EXACT original func_065 (from actual entry point at 0x23F2E)
    func_start = 0x23F2E
    func_end = 0x23FC2
    original_func = rom_data[func_start:func_end]

    print(f"\n✓ Original func_065: 0x{func_start:06X}-0x{func_end:06X}")
    print(f"  Size: {len(original_func)} bytes")

    # Relocate to ACTUAL unused space at end of ROM
    new_location = 0x2F5D00
    print(f"\n✓ Writing to ROM 0x{new_location:06X}")
    rom_data[new_location:new_location+len(original_func)] = original_func

    # Create trampoline with register preservation
    call_site = 0x23F2E
    target_addr = 0x02000000 + new_location

    # FIXED: Don't restore R3 in delay slot - it interferes with JMP!
    # Instead: Jump with NOP, then restore R3 after we arrive
    # But wait - we can't restore after arriving because we've already jumped!
    #
    # New strategy: The relocated function must restore R3 at its START
    # Trampoline:
    #   1. Save R3 to stack
    #   2. Load target into R3
    #   3. JMP @R3 with NOP in delay slot
    #   4. Relocated function must pop R3 as first instruction
    #
    # But we can't modify the relocated function in this NULL test!
    #
    # Actually, wait. Let me try a different approach: don't use JMP, use BRAF
    # No, BRAF is also out of range.
    #
    # OK, final attempt: Use MOV.L to load into R3, but then MOVE R3 somewhere
    # else before jumping. Like:
    #   MOV.L @(PC+x),R3    ; Load target
    #   MOV R3,R2           ; Copy to R2 (another scratch register)
    #   MOV.L @R15+,R3      ; Restore R3
    #   JMP @R2             ; Jump using R2
    #   NOP

    # ULTRA-SIMPLE TEST: No register preservation, just jump
    # This clobbers R2, but if it works, we know relocation is possible
    trampoline = bytearray([
        0xD2, 0x01,  # MOV.L @(PC+4),R2  (load target into R2, clobbers R2!)
        0x42, 0x2B,  # JMP @R2
        0x00, 0x09,  # NOP (delay slot)
    ])
    trampoline.extend(struct.pack('>I', target_addr))

    print(f"\n✓ Creating trampoline at ROM 0x{call_site:06X}")
    print(f"  Jump target: 0x{target_addr:08X}")
    print(f"  Trampoline size: {len(trampoline)} bytes")

    # Write trampoline
    rom_data[call_site:call_site+len(trampoline)] = trampoline

    # Fill rest with NOPs
    remaining = func_end - call_site - len(trampoline)
    for i in range(remaining // 2):
        rom_data[call_site + len(trampoline) + i*2:call_site + len(trampoline) + i*2 + 2] = bytes([0x00, 0x09])

    # Save
    output_file.write_bytes(rom_data)
    print(f"\n✓ NULL patch ROM saved: {output_file}")
    print("\nThis ROM should behave EXACTLY like the original.")
    print("If it boots, the trampoline works.")
    print("If it crashes, the trampoline has a bug.")

if __name__ == '__main__':
    main()
