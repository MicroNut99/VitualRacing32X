#!/usr/bin/env python3
"""
Phase 17: Cycle Count Measurement

Measures actual cycle cost of Slave vertex transform using SH2 FRT.

Adds cycle measurement to Phase 16 test:
- Slave reads FRT (Free Running Timer) before transform
- Slave reads FRT after transform
- Slave stores delta at 0x22000300 (cycle count for 4 vertices)

SH2 FRT (Free Running Timer):
- FRC register at 0xFFFFFE12 (16-bit counter)
- Counts up at CPU clock / 8 (23MHz / 8 = 2.875 MHz)
- Each tick = ~8 CPU cycles at 23 MHz

Memory Layout:
    0x22000200-0x2200023F: Input vertices (same as Phase 16)
    0x22000240-0x2200027F: Matrix (same as Phase 16)
    0x22000280-0x220002BF: Output vertices (same as Phase 16)
    0x220002FC: Done flag (same as Phase 16)
    0x22000300: Cycle count (FRT delta × 8)
    0x22000304: FRT start value (for debugging)
    0x22000308: FRT end value (for debugging)

Usage:
    python3 tools/inject_phase17_cycle_measurement.py build/vr_baseline_probe.32x build/vr_phase17.32x
"""

import sys
import struct
from pathlib import Path

# Reuse Phase 16 memory layout
INPUT_VERTICES_ADDR = 0x22000200
MATRIX_ADDR = 0x22000240
OUTPUT_VERTICES_ADDR = 0x22000280
DONE_FLAG_ADDR = 0x220002FC

# New: cycle measurement storage
CYCLE_COUNT_ADDR = 0x22000300    # Total cycles (FRT_delta × 8)
FRT_START_ADDR = 0x22000304      # FRT value at start (debug)
FRT_END_ADDR = 0x22000308        # FRT value at end (debug)

COMM4_ADDR = 0x20004028
COMM6_ADDR = 0x2000402C

# SH2 FRT registers
FRC_ADDR = 0xFFFFFE12  # Free Running Counter (16-bit)

SIGNATURE = 0xCAFE1234
DONE_VALUE = 0x00010001

def to_fixed(f): return int(f * 65536) & 0xFFFFFFFF

INPUT_VERTICES = [
    [to_fixed(1.0), to_fixed(0.0), to_fixed(0.0), to_fixed(1.0)],
    [to_fixed(0.0), to_fixed(1.0), to_fixed(0.0), to_fixed(1.0)],
    [to_fixed(0.0), to_fixed(0.0), to_fixed(1.0), to_fixed(1.0)],
    [to_fixed(1.0), to_fixed(1.0), to_fixed(1.0), SIGNATURE],
]

IDENTITY_MATRIX = [
    to_fixed(1.0), to_fixed(0.0), to_fixed(0.0), to_fixed(0.0),
    to_fixed(0.0), to_fixed(1.0), to_fixed(0.0), to_fixed(0.0),
    to_fixed(0.0), to_fixed(0.0), to_fixed(1.0), to_fixed(0.0),
    to_fixed(0.0), to_fixed(0.0), to_fixed(0.0), to_fixed(1.0),
]


def create_cycle_measured_handler(handler_addr: int) -> bytes:
    """
    Create Slave handler with cycle measurement.

    Uses SH2 FRT (Free Running Counter) to measure cycles.
    FRT increments at CPU_CLK / 8, so each tick = 8 CPU cycles.
    """
    code = bytearray()

    # === READ FRT START ===
    frc_start_mov = len(code)
    code.extend([0xD0, 0x00])   # MOV.L @(disp,PC),R0 - FRC address

    code.extend([0x90, 0x02])   # MOV.W @R0,R0 - read FRC (16-bit)
    code.extend([0x60, 0x0F])   # EXTU.W R0,R0 - zero extend to 32-bit

    # Save FRT start value
    code.extend([0x6D, 0x03])   # MOV R0,R13 - R13 = FRT_start

    frt_start_stor_mov = len(code)
    code.extend([0xD1, 0x00])   # MOV.L @(disp,PC),R1 - FRT_start storage addr
    code.extend([0x20, 0xD2])   # MOV.L R13,@R1

    # === TRANSFORM CODE (same as Phase 16) ===

    # Load base addresses
    input_mov = len(code)
    code.extend([0xD4, 0x00])   # MOV.L @(disp,PC),R4 - input vertices

    matrix_mov = len(code)
    code.extend([0xD5, 0x00])   # MOV.L @(disp,PC),R5 - matrix

    output_mov = len(code)
    code.extend([0xD6, 0x00])   # MOV.L @(disp,PC),R6 - output vertices

    # R7 = vertex counter
    code.extend([0xE7, 0x04])   # MOV #4,R7

    # === VERTEX LOOP (abbreviated - same logic as Phase 16) ===
    vertex_loop_start = len(code)

    # Load vertex
    code.extend([0x68, 0x46])   # MOV.L @R4+,R8  - x
    code.extend([0x69, 0x46])   # MOV.L @R4+,R9  - y
    code.extend([0x6A, 0x46])   # MOV.L @R4+,R10 - z
    code.extend([0x6B, 0x46])   # MOV.L @R4+,R11 - w

    # Save matrix pointer
    code.extend([0x2F, 0x56])   # push R5

    # Transform X component
    code.extend([0x00, 0x28])   # CLRMAC
    for _ in range(4):  # M[0-3] * (x,y,z,w)
        code.extend([0x60, 0x56])   # MOV.L @R5+,R0
        code.extend([0x38, 0x0D])   # DMULS.L R0,R8 (first component)
        code.extend([0x02, 0x0A])   # STS MACH,R2
        code.extend([0x03, 0x1A])   # STS MACL,R3
        code.extend([0x23, 0x2D])   # XTRCT R2,R3
        if _ == 0:
            code.extend([0x6C, 0x33])   # MOV R3,R12
        else:
            code.extend([0x3C, 0x3C])   # ADD R3,R12
    code.extend([0x26, 0xC2])   # MOV.L R12,@R6
    code.extend([0x76, 0x04])   # ADD #4,R6

    # Transform Y component (similar pattern)
    code.extend([0x00, 0x28])   # CLRMAC
    for _ in range(4):
        code.extend([0x60, 0x56])   # MOV.L @R5+,R0
        code.extend([0x39, 0x0D])   # DMULS.L R0,R9
        code.extend([0x02, 0x0A])   # STS MACH,R2
        code.extend([0x03, 0x1A])   # STS MACL,R3
        code.extend([0x23, 0x2D])   # XTRCT R2,R3
        if _ == 0:
            code.extend([0x6C, 0x33])
        else:
            code.extend([0x3C, 0x3C])
    code.extend([0x26, 0xC2])
    code.extend([0x76, 0x04])

    # Transform Z component
    code.extend([0x00, 0x28])
    for _ in range(4):
        code.extend([0x60, 0x56])
        code.extend([0x3A, 0x0D])   # DMULS.L R0,R10
        code.extend([0x02, 0x0A])
        code.extend([0x03, 0x1A])
        code.extend([0x23, 0x2D])
        if _ == 0:
            code.extend([0x6C, 0x33])
        else:
            code.extend([0x3C, 0x3C])
    code.extend([0x26, 0xC2])
    code.extend([0x76, 0x04])

    # Transform W component
    code.extend([0x00, 0x28])
    for _ in range(4):
        code.extend([0x60, 0x56])
        code.extend([0x3B, 0x0D])   # DMULS.L R0,R11
        code.extend([0x02, 0x0A])
        code.extend([0x03, 0x1A])
        code.extend([0x23, 0x2D])
        if _ == 0:
            code.extend([0x6C, 0x33])
        else:
            code.extend([0x3C, 0x3C])
    code.extend([0x26, 0xC2])
    code.extend([0x76, 0x04])

    # Restore matrix pointer and loop
    code.extend([0x65, 0xF6])   # pop R5
    code.extend([0x47, 0x10])   # DT R7

    vertex_loop_bf = len(code)
    bf_disp = (vertex_loop_start - (vertex_loop_bf + 4)) // 2
    code.extend([0x8B, bf_disp & 0xFF])  # BF vertex_loop

    # === READ FRT END ===
    frc_end_mov = len(code)
    code.extend([0xD0, 0x00])   # MOV.L @(disp,PC),R0 - FRC address

    code.extend([0x90, 0x02])   # MOV.W @R0,R0 - read FRC
    code.extend([0x60, 0x0F])   # EXTU.W R0,R0

    # Save FRT end value
    code.extend([0x6E, 0x03])   # MOV R0,R14 - R14 = FRT_end

    frt_end_stor_mov = len(code)
    code.extend([0xD1, 0x00])   # MOV.L @(disp,PC),R1 - FRT_end storage addr
    code.extend([0x20, 0xE2])   # MOV.L R14,@R1

    # === CALCULATE CYCLE COUNT ===
    # delta = FRT_end - FRT_start
    code.extend([0x3E, 0xD8])   # SUB R13,R14 - R14 = delta (in FRT ticks)

    # Convert to CPU cycles: delta × 8
    code.extend([0x6E, 0xE3])   # MOV R14,R14 (identity for clarity)
    code.extend([0x4E, 0x08])   # SHLL2 R14 - R14 × 4
    code.extend([0x4E, 0x00])   # SHLL R14  - R14 × 2 (total × 8)

    # Store cycle count
    cycle_count_mov = len(code)
    code.extend([0xD1, 0x00])   # MOV.L @(disp,PC),R1 - cycle count addr
    code.extend([0x21, 0xE2])   # MOV.L R14,@R1

    # === Write done flag ===
    done_flag_mov = len(code)
    code.extend([0xD0, 0x00])
    done_value_mov = len(code)
    code.extend([0xD1, 0x00])
    code.extend([0x20, 0x12])

    # === Increment COMM4 ===
    comm4_mov = len(code)
    code.extend([0xD0, 0x00])
    code.extend([0x61, 0x02])
    code.extend([0x71, 0x01])
    code.extend([0x20, 0x12])

    # Return
    code.extend([0x00, 0x0B])
    code.extend([0x00, 0x09])

    # Align
    while len(code) % 4 != 0:
        code.extend([0x00, 0x09])

    # === Literal pool ===
    frc_lit = len(code)
    code.extend(struct.pack('>I', FRC_ADDR))

    frt_start_stor_lit = len(code)
    code.extend(struct.pack('>I', FRT_START_ADDR))

    input_lit = len(code)
    code.extend(struct.pack('>I', INPUT_VERTICES_ADDR))

    matrix_lit = len(code)
    code.extend(struct.pack('>I', MATRIX_ADDR))

    output_lit = len(code)
    code.extend(struct.pack('>I', OUTPUT_VERTICES_ADDR))

    frc_end_lit = len(code)
    code.extend(struct.pack('>I', FRC_ADDR))

    frt_end_stor_lit = len(code)
    code.extend(struct.pack('>I', FRT_END_ADDR))

    cycle_count_lit = len(code)
    code.extend(struct.pack('>I', CYCLE_COUNT_ADDR))

    done_flag_lit = len(code)
    code.extend(struct.pack('>I', DONE_FLAG_ADDR))

    done_value_lit = len(code)
    code.extend(struct.pack('>I', DONE_VALUE))

    comm4_lit = len(code)
    code.extend(struct.pack('>I', COMM4_ADDR))

    # Fix displacements
    def calc_disp(instr_offset, literal_offset):
        pc = handler_addr + instr_offset
        base = (pc & ~3) + 4
        return (handler_addr + literal_offset - base) // 4

    code[frc_start_mov + 1] = calc_disp(frc_start_mov, frc_lit)
    code[frt_start_stor_mov + 1] = calc_disp(frt_start_stor_mov, frt_start_stor_lit)
    code[input_mov + 1] = calc_disp(input_mov, input_lit)
    code[matrix_mov + 1] = calc_disp(matrix_mov, matrix_lit)
    code[output_mov + 1] = calc_disp(output_mov, output_lit)
    code[frc_end_mov + 1] = calc_disp(frc_end_mov, frc_end_lit)
    code[frt_end_stor_mov + 1] = calc_disp(frt_end_stor_mov, frt_end_stor_lit)
    code[cycle_count_mov + 1] = calc_disp(cycle_count_mov, cycle_count_lit)
    code[done_flag_mov + 1] = calc_disp(done_flag_mov, done_flag_lit)
    code[done_value_mov + 1] = calc_disp(done_value_mov, done_value_lit)
    code[comm4_mov + 1] = calc_disp(comm4_mov, comm4_lit)

    return bytes(code)


def create_phase17_vblank_code(code_start_addr: int) -> bytes:
    """Reuse Phase 16 VBlank code (unchanged)."""
    # Import from Phase 16 for consistency
    from inject_phase16_vertex_test import create_phase16_vblank_code
    return create_phase16_vblank_code(code_start_addr)


def inject_phase17(input_rom: str, output_rom: str) -> bool:
    """Inject Phase 17 cycle measurement test."""

    print("=" * 70)
    print("PHASE 17: CYCLE COUNT MEASUREMENT")
    print("=" * 70)
    print()

    rom_path = Path(input_rom)
    if not rom_path.exists():
        print(f"ROM not found: {input_rom}")
        return False

    rom_data = bytearray(rom_path.read_bytes())
    print(f"ROM loaded: {len(rom_data):,} bytes")
    print()

    # Inject handler with cycle measurement
    handler_offset = 0x300027
    handler_addr = 0x02300027

    new_handler = create_cycle_measured_handler(handler_addr)
    print(f"Slave handler size: {len(new_handler)} bytes")

    rom_data[handler_offset:handler_offset + len(new_handler)] = new_handler
    print(f"Injected handler at ROM 0x{handler_offset:06X}")
    print()

    # Inject VBlank code
    vblank_offset = 0x300200
    vblank_addr = 0x02300200

    vblank_code = create_phase17_vblank_code(vblank_addr)
    print(f"VBlank code size: {len(vblank_code)} bytes")

    rom_data[vblank_offset:vblank_offset + len(vblank_code)] = vblank_code
    print(f"Injected VBlank at ROM 0x{vblank_offset:06X}")
    print()

    # Update VBlank redirect
    vblank_func = 0x243E0
    new_redirect = bytearray()
    new_redirect.extend([0xD1, 0x01])
    new_redirect.extend([0x41, 0x2B])
    new_redirect.extend([0x00, 0x09])
    new_redirect.extend([0x00, 0x09])
    new_redirect.extend(struct.pack('>I', vblank_addr))

    rom_data[vblank_func:vblank_func + len(new_redirect)] = new_redirect
    print(f"Updated VBlank redirect at ROM 0x{vblank_func:06X}")
    print()

    # Write output
    Path(output_rom).write_bytes(rom_data)
    print(f"Output: {output_rom}")
    print()

    # Summary
    print("=" * 70)
    print("CYCLE MEASUREMENT")
    print("=" * 70)
    print()
    print("SH2 FRT (Free Running Timer):")
    print("  - Counts at CPU_CLK / 8 = 23MHz / 8 = 2.875 MHz")
    print("  - Each FRT tick = 8 CPU cycles")
    print("  - 16-bit counter (wraps at 65536)")
    print()
    print("Memory locations:")
    print(f"  0x{CYCLE_COUNT_ADDR:08X}: Total CPU cycles for 4-vertex transform")
    print(f"  0x{FRT_START_ADDR:08X}: FRT value at start (debug)")
    print(f"  0x{FRT_END_ADDR:08X}: FRT value at end (debug)")
    print()
    print("Expected cycle counts:")
    print("  Per vertex: 16 DMULS.L + 12 ADD + overhead")
    print("    - DMULS.L: 2-3 cycles each × 16 = 32-48 cycles")
    print("    - ADD: 1 cycle each × 12 = 12 cycles")
    print("    - Overhead: ~50 cycles (loads, stores, loop)")
    print("  Per vertex total: ~94-110 cycles")
    print("  4 vertices: ~376-440 cycles")
    print()
    print("VALIDATION:")
    print("  1. ROM boots without crash")
    print("  2. Cycle count at 0x22000300 is non-zero")
    print("  3. Cycle count is reasonable (~300-500 range)")
    print()

    return True


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 inject_phase17_cycle_measurement.py <input.32x> <output.32x>")
        print()
        print("Example:")
        print("  python3 inject_phase17_cycle_measurement.py build/vr_baseline_probe.32x build/vr_phase17.32x")
        sys.exit(1)

    success = inject_phase17(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
