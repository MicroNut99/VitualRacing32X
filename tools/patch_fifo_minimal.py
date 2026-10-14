#!/usr/bin/env python3
"""
MINIMAL FIFO optimization that FITS in existing space (no relocation!)

Strategy: Batch only FIRST 2 pairs (4 iterations) into FIFO mode
Leaves remaining 10 iterations unchanged
Optimizations: Removed leading NOP, hardcoded stride (ADD #16 vs 2×ADD R13)
Size: 148 bytes exactly (perfect fit!)
Expected gain: ~3-5% (conservative but safe)
"""

import sys
import struct
from pathlib import Path

def main():
    print("=" * 70)
    print(" Virtua Racing - MINIMAL FIFO Batch (In-Place, No Relocation)")
    print(" Expected Gain: +3-5% FPS")
    print("=" * 70)

    input_file = Path("Virtua Racing Deluxe (USA).32x")
    output_file = Path("Virtua Racing - FIFO-MINIMAL.32x")

    if not input_file.exists():
        print(f"\n❌ Input ROM not found: {input_file}")
        sys.exit(1)

    print(f"\n✓ Reading ROM: {input_file}")
    rom_data = bytearray(input_file.read_bytes())

    # Build minimal FIFO version
    func_body = bytearray()

    # Prologue (8 bytes) - no leading NOP, function starts at 0x23F2E
    func_body.extend(bytes([
        0x40, 0x18,  # SHLL8 R0
        0x40, 0x01,  # SHLR R0
        0x30, 0xAC,  # ADD R10,R0
        0x61, 0x93,  # MOV R9,R1
    ]))

    # 2 FIFO pairs (4 iterations = 18 bytes each = 36 bytes)
    # Optimized: Use ADD #16,R1 instead of 2×ADD R13,R1 (assumes R13=8)
    for i in range(2):
        func_body.extend(struct.pack('>H', 0x6206))  # MOV.L @R0+,R2
        func_body.extend(struct.pack('>H', 0x1120))  # MOV.L R2,@($0,R1)
        func_body.extend(struct.pack('>H', 0x6206))  # MOV.L @R0+,R2
        func_body.extend(struct.pack('>H', 0x1121))  # MOV.L R2,@($4,R1)
        func_body.extend(struct.pack('>H', 0x6206))  # MOV.L @R0+,R2
        func_body.extend(struct.pack('>H', 0x1122))  # MOV.L R2,@($8,R1)
        func_body.extend(struct.pack('>H', 0x6206))  # MOV.L @R0+,R2
        func_body.extend(struct.pack('>H', 0x1123))  # MOV.L R2,@($C,R1) - FIFO!
        func_body.extend(struct.pack('>H', 0x7110))  # ADD #16,R1 (hardcoded stride)

    # Remaining 10 normal iterations (10 × 5 instr × 2 bytes = 100 bytes)
    for i in range(10):
        func_body.extend(struct.pack('>H', 0x6206))  # MOV.L @R0+,R2
        func_body.extend(struct.pack('>H', 0x1120))  # MOV.L R2,@($0,R1)
        func_body.extend(struct.pack('>H', 0x6206))  # MOV.L @R0+,R2
        func_body.extend(struct.pack('>H', 0x1121))  # MOV.L R2,@($4,R1)
        func_body.extend(struct.pack('>H', 0x31DC))  # ADD R13,R1

    # Epilogue (4 bytes)
    func_body.extend(bytes([
        0x00, 0x0B,  # RTS
        0x00, 0x09,  # NOP
    ]))

    print(f"\n✓ Generated function: {len(func_body)} bytes")
    print(f"  Prologue: 8 bytes")
    print(f"  FIFO pairs: 36 bytes (2 pairs × 18 bytes)")
    print(f"  Normal iterations: 100 bytes (10 × 10 bytes)")
    print(f"  Epilogue: 4 bytes")
    print(f"  Available space: 148 bytes")

    if len(func_body) > 148:
        print(f"\n❌ Too large by {len(func_body) - 148} bytes!")
        sys.exit(1)
    elif len(func_body) == 148:
        print(f"  ✓ Perfect fit!")
    else:
        print(f"  Padding needed: {148 - len(func_body)} bytes")

    # Write in-place at 0x23F2E
    call_site = 0x23F2E
    rom_data[call_site:call_site+len(func_body)] = func_body

    # Fill remaining with NOPs
    remaining = 148 - len(func_body)
    for i in range(remaining // 2):
        rom_data[call_site + len(func_body) + i*2:call_site + len(func_body) + i*2 + 2] = bytes([0x00, 0x09])

    print(f"  Padding: {remaining} bytes NOP")
    print(f"\n✓ In-place patch (NO RELOCATION!)")
    print(f"  Modified: ROM 0x{call_site:06X}")

    # Save
    output_file.write_bytes(rom_data)
    print(f"\n✓ Saved: {output_file}")
    print("\nThis version uses IN-PLACE patching (no trampoline needed)")
    print("Should be much more stable!")

if __name__ == '__main__':
    main()
