#!/usr/bin/env python3
"""
Phase 17.1: Wraparound-Safe Cycle Measurement

Fixes Phase 17 timing measurement to handle FRT wraparound.

FRT Issues Addressed:
1. Wraparound: 16-bit counter wraps every ~22.8ms at 2.875 MHz
   - Fix: if (FRT_end < FRT_start) add 0x10000 before subtract

2. Interrupt interference: ISR cycles included in measurement
   - Note: Slave SH2 is mostly idle, interrupts rare in practice
   - Handler does NOT mask interrupts (would require saving SR)
   - Measurement includes any ISR overhead that occurs

Algorithm:
    FRT_start = read_frt()
    ... transform work ...
    FRT_end = read_frt()

    if (FRT_end < FRT_start):
        delta = (0x10000 + FRT_end) - FRT_start  # Wrapped
    else:
        delta = FRT_end - FRT_start               # Normal

    cycles = delta × 8

Memory Layout (same as Phase 17):
    0x22000300: Cycle count
    0x22000304: FRT start (debug)
    0x22000308: FRT end (debug)
    0x2200030C: Wrap flag (1 if wraparound occurred)

Usage:
    python3 tools/inject_phase17_1_cycle_safe.py build/vr_baseline_probe.32x build/vr_phase17_1.32x
"""

import sys
import struct
from pathlib import Path

INPUT_VERTICES_ADDR = 0x22000200
MATRIX_ADDR = 0x22000240
OUTPUT_VERTICES_ADDR = 0x22000280
DONE_FLAG_ADDR = 0x220002FC

CYCLE_COUNT_ADDR = 0x22000300
FRT_START_ADDR = 0x22000304
FRT_END_ADDR = 0x22000308
WRAP_FLAG_ADDR = 0x2200030C  # NEW: 1 if wraparound occurred

COMM4_ADDR = 0x20004028
COMM6_ADDR = 0x2000402C

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


def create_wraparound_safe_handler(handler_addr: int) -> bytes:
    """
    Create Slave handler with wraparound-safe cycle measurement.
    """
    code = bytearray()

    # === READ FRT START ===
    frc_start_mov = len(code)
    code.extend([0xD0, 0x00])   # MOV.L @(disp,PC),R0 - FRC address
    code.extend([0x90, 0x02])   # MOV.W @R0,R0 - read FRC (16-bit)
    code.extend([0x60, 0x0F])   # EXTU.W R0,R0 - zero extend to 32-bit

    code.extend([0x6D, 0x03])   # MOV R0,R13 - R13 = FRT_start

    frt_start_stor_mov = len(code)
    code.extend([0xD1, 0x00])   # MOV.L @(disp,PC),R1
    code.extend([0x20, 0xD2])   # MOV.L R13,@R1

    # === TRANSFORM CODE (abbreviated - same as Phase 17) ===

    input_mov = len(code)
    code.extend([0xD4, 0x00])   # MOV.L @(disp,PC),R4

    matrix_mov = len(code)
    code.extend([0xD5, 0x00])   # MOV.L @(disp,PC),R5

    output_mov = len(code)
    code.extend([0xD6, 0x00])   # MOV.L @(disp,PC),R6

    code.extend([0xE7, 0x04])   # MOV #4,R7

    vertex_loop_start = len(code)

    # Load vertex
    code.extend([0x68, 0x46])   # MOV.L @R4+,R8
    code.extend([0x69, 0x46])   # MOV.L @R4+,R9
    code.extend([0x6A, 0x46])   # MOV.L @R4+,R10
    code.extend([0x6B, 0x46])   # MOV.L @R4+,R11

    code.extend([0x2F, 0x56])   # push R5

    # Transform X,Y,Z,W (4 components × same pattern)
    for component_idx in range(4):
        code.extend([0x00, 0x28])   # CLRMAC
        for matrix_row in range(4):
            code.extend([0x60, 0x56])   # MOV.L @R5+,R0

            # Select which vertex component to multiply
            if matrix_row == 0:
                code.extend([0x38, 0x0D])   # DMULS.L R0,R8
            elif matrix_row == 1:
                code.extend([0x39, 0x0D])   # DMULS.L R0,R9
            elif matrix_row == 2:
                code.extend([0x3A, 0x0D])   # DMULS.L R0,R10
            else:
                code.extend([0x3B, 0x0D])   # DMULS.L R0,R11

            code.extend([0x02, 0x0A])   # STS MACH,R2
            code.extend([0x03, 0x1A])   # STS MACL,R3
            code.extend([0x23, 0x2D])   # XTRCT R2,R3

            if matrix_row == 0:
                code.extend([0x6C, 0x33])   # MOV R3,R12
            else:
                code.extend([0x3C, 0x3C])   # ADD R3,R12

        code.extend([0x26, 0xC2])   # MOV.L R12,@R6
        code.extend([0x76, 0x04])   # ADD #4,R6

    code.extend([0x65, 0xF6])   # pop R5
    code.extend([0x47, 0x10])   # DT R7

    vertex_loop_bf = len(code)
    bf_disp = (vertex_loop_start - (vertex_loop_bf + 4)) // 2
    code.extend([0x8B, bf_disp & 0xFF])  # BF vertex_loop

    # === READ FRT END ===
    frc_end_mov = len(code)
    code.extend([0xD0, 0x00])   # MOV.L @(disp,PC),R0 - FRC address
    code.extend([0x90, 0x02])   # MOV.W @R0,R0
    code.extend([0x60, 0x0F])   # EXTU.W R0,R0

    code.extend([0x6E, 0x03])   # MOV R0,R14 - R14 = FRT_end

    frt_end_stor_mov = len(code)
    code.extend([0xD1, 0x00])   # MOV.L @(disp,PC),R1
    code.extend([0x20, 0xE2])   # MOV.L R14,@R1

    # === WRAPAROUND-SAFE DELTA CALCULATION ===
    # Compare FRT_end (R14) with FRT_start (R13)
    code.extend([0x3E, 0xD3])   # CMP/GT R13,R14 - T=1 if R14 > R13 (no wrap)

    # Branch if no wraparound (normal case)
    no_wrap_label = len(code)
    code.extend([0x89, 0x00])   # BT no_wrap (placeholder displacement)

    # === WRAPAROUND PATH ===
    # delta = (0x10000 + FRT_end) - FRT_start
    code.extend([0xE0, 0x01])   # MOV #1,R0
    code.extend([0x40, 0x08])   # SHLL2 R0      ; R0 = 4
    code.extend([0x40, 0x08])   # SHLL2 R0      ; R0 = 16
    code.extend([0x40, 0x08])   # SHLL2 R0      ; R0 = 64
    code.extend([0x40, 0x08])   # SHLL2 R0      ; R0 = 256
    code.extend([0x40, 0x08])   # SHLL2 R0      ; R0 = 1024
    code.extend([0x40, 0x08])   # SHLL2 R0      ; R0 = 4096
    code.extend([0x40, 0x08])   # SHLL2 R0      ; R0 = 16384
    code.extend([0x40, 0x08])   # SHLL2 R0      ; R0 = 65536 = 0x10000

    code.extend([0x30, 0xEC])   # ADD R14,R0    ; R0 = 0x10000 + FRT_end
    code.extend([0x30, 0xD8])   # SUB R13,R0    ; R0 = delta (wrapped)

    # Set wrap flag = 1
    code.extend([0xE1, 0x01])   # MOV #1,R1
    wrap_flag_stor_mov1 = len(code)
    code.extend([0xD2, 0x00])   # MOV.L @(disp,PC),R2 - wrap flag addr
    code.extend([0x22, 0x12])   # MOV.L R1,@R2

    # Jump to cycle conversion
    after_wrap_label = len(code)
    code.extend([0xA0, 0x00])   # BRA after_delta (placeholder)
    code.extend([0x00, 0x09])   # NOP (delay slot)

    # === NO WRAPAROUND PATH ===
    no_wrap_offset = len(code)
    # Update BT displacement
    bt_disp = (no_wrap_offset - (no_wrap_label + 4)) // 2
    code[no_wrap_label + 1] = bt_disp & 0xFF

    # delta = FRT_end - FRT_start (normal)
    code.extend([0x60, 0xE3])   # MOV R14,R0    ; R0 = FRT_end
    code.extend([0x30, 0xD8])   # SUB R13,R0    ; R0 = delta

    # Set wrap flag = 0
    code.extend([0xE1, 0x00])   # MOV #0,R1
    wrap_flag_stor_mov2 = len(code)
    code.extend([0xD2, 0x00])   # MOV.L @(disp,PC),R2
    code.extend([0x22, 0x12])   # MOV.L R1,@R2

    # === CONVERT DELTA TO CPU CYCLES ===
    after_delta_offset = len(code)
    # Update BRA displacement
    bra_disp = (after_delta_offset - (after_wrap_label + 4)) // 2
    if bra_disp < 0:
        bra_disp = (bra_disp & 0xFF) | 0x100  # Sign extend for BRA
    code[after_wrap_label + 1] = bra_disp & 0xFF

    # R0 = delta (in FRT ticks), convert to cycles: delta × 8
    code.extend([0x40, 0x08])   # SHLL2 R0  ; × 4
    code.extend([0x40, 0x00])   # SHLL R0   ; × 2 (total × 8)

    # Store cycle count
    cycle_count_mov = len(code)
    code.extend([0xD1, 0x00])   # MOV.L @(disp,PC),R1
    code.extend([0x20, 0x12])   # MOV.L R0,@R1

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

    wrap_flag_lit1 = len(code)
    code.extend(struct.pack('>I', WRAP_FLAG_ADDR))

    wrap_flag_lit2 = len(code)
    code.extend(struct.pack('>I', WRAP_FLAG_ADDR))

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
    code[wrap_flag_stor_mov1 + 1] = calc_disp(wrap_flag_stor_mov1, wrap_flag_lit1)
    code[wrap_flag_stor_mov2 + 1] = calc_disp(wrap_flag_stor_mov2, wrap_flag_lit2)
    code[cycle_count_mov + 1] = calc_disp(cycle_count_mov, cycle_count_lit)
    code[done_flag_mov + 1] = calc_disp(done_flag_mov, done_flag_lit)
    code[done_value_mov + 1] = calc_disp(done_value_mov, done_value_lit)
    code[comm4_mov + 1] = calc_disp(comm4_mov, comm4_lit)

    return bytes(code)


def create_phase17_1_vblank_code(code_start_addr: int) -> bytes:
    """Reuse Phase 16 VBlank code."""
    from inject_phase16_vertex_test import create_phase16_vblank_code
    return create_phase16_vblank_code(code_start_addr)


def inject_phase17_1(input_rom: str, output_rom: str) -> bool:
    """Inject Phase 17.1 wraparound-safe measurement."""

    print("=" * 70)
    print("PHASE 17.1: WRAPAROUND-SAFE CYCLE MEASUREMENT")
    print("=" * 70)
    print()

    rom_path = Path(input_rom)
    if not rom_path.exists():
        print(f"ROM not found: {input_rom}")
        return False

    rom_data = bytearray(rom_path.read_bytes())
    print(f"ROM loaded: {len(rom_data):,} bytes")
    print()

    # Inject handler
    handler_offset = 0x300027
    handler_addr = 0x02300027

    new_handler = create_wraparound_safe_handler(handler_addr)
    print(f"Slave handler size: {len(new_handler)} bytes")

    rom_data[handler_offset:handler_offset + len(new_handler)] = new_handler
    print(f"Injected handler at ROM 0x{handler_offset:06X}")
    print()

    # Inject VBlank
    vblank_offset = 0x300200
    vblank_addr = 0x02300200

    vblank_code = create_phase17_1_vblank_code(vblank_addr)
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
    print(f"Updated VBlank redirect")
    print()

    # Write output
    Path(output_rom).write_bytes(rom_data)
    print(f"Output: {output_rom}")
    print()

    # Summary
    print("=" * 70)
    print("IMPROVEMENTS OVER PHASE 17")
    print("=" * 70)
    print()
    print("1. WRAPAROUND HANDLING:")
    print("   - Detects if FRT_end < FRT_start")
    print("   - Adds 0x10000 before subtraction if wrapped")
    print("   - Sets wrap flag at 0x2200030C for debugging")
    print()
    print("2. INTERRUPT AWARENESS:")
    print("   - Handler does NOT mask interrupts")
    print("   - Measurement includes ISR overhead if any occurs")
    print("   - Slave SH2 is mostly idle, so ISRs are rare in practice")
    print()
    print("Memory locations:")
    print(f"  0x{CYCLE_COUNT_ADDR:08X}: CPU cycles (accurate even if wrapped)")
    print(f"  0x{FRT_START_ADDR:08X}: FRT start value")
    print(f"  0x{FRT_END_ADDR:08X}: FRT end value")
    print(f"  0x{WRAP_FLAG_ADDR:08X}: Wrap flag (1=wrapped, 0=normal)")
    print()
    print("Expected cycle count: ~376-440 cycles (same as Phase 17)")
    print("Wrap probability for 4 vertices: ~0.02% (very unlikely)")
    print()
    print("=" * 70)
    print("VALIDATION")
    print("=" * 70)
    print()
    print("1. ROM boots without crash")
    print("2. Cycle count is reasonable (~300-500)")
    print("3. Wrap flag is 0 (unlikely to see 1 for small tests)")
    print("4. Measurement is now safe for scaling to 64+ vertices")
    print()

    return True


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 inject_phase17_1_cycle_safe.py <input.32x> <output.32x>")
        print()
        print("Example:")
        print("  python3 inject_phase17_1_cycle_safe.py build/vr_baseline_probe.32x build/vr_phase17_1.32x")
        sys.exit(1)

    success = inject_phase17_1(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
