#!/usr/bin/env python3
"""
Phase 15.6: Slave 16.16 Fixed-Point Multiply Test

Proves the Slave can perform the core arithmetic operation used in vertex transforms:
- 32x32 → 64-bit signed multiply (DMULS.L)
- Extract middle 32 bits for 16.16 result (XTRCT)

Test setup:
- Input A: 0x22000200 (16.16 fixed-point value)
- Input B: 0x22000204 (16.16 fixed-point value)
- Output:  0x22000210 (A * B in 16.16 format)
- COMM4:   Increments each frame (proves handler ran)

Test values (set by Master each frame):
- A = 0x00020000 (2.0 in 16.16)
- B = 0x00030000 (3.0 in 16.16)
- Expected result = 0x00060000 (6.0 in 16.16)

The multiply algorithm for 16.16:
    result = (A * B) >> 16

In SH2 assembly:
    DMULS.L Rm, Rn    ; 32x32 → 64-bit result in MACH:MACL
    STS     MACH, Rh  ; Get high 32 bits
    STS     MACL, Rl  ; Get low 32 bits
    XTRCT   Rh, Rl    ; Rl = (Rh[15:0] << 16) | (Rl[31:16])
                      ; This extracts bits [47:16] of the 64-bit result

Usage:
    python3 tools/inject_multiply_test.py build/vr_baseline_probe.32x build/vr_multiply_test.32x
"""

import sys
import struct
from pathlib import Path

# Test values: 2.0 * 3.0 = 6.0 in 16.16 fixed-point
VALUE_A = 0x00020000  # 2.0
VALUE_B = 0x00030000  # 3.0
EXPECTED = 0x00060000  # 6.0

INPUT_A_ADDR = 0x22000200
INPUT_B_ADDR = 0x22000204
OUTPUT_ADDR = 0x22000210
COMM4_ADDR = 0x20004028


def create_multiply_handler(handler_addr: int) -> bytes:
    """
    Create SH2 handler that multiplies two 16.16 values.

    Handler logic:
        R4 = &input_A (0x22000200)
        R5 = &input_B (0x22000204)
        R6 = &output (0x22000210)

        R0 = *R4 (load A)
        R1 = *R5 (load B)
        DMULS.L R0, R1    ; 64-bit result in MACH:MACL
        STS MACH, R2      ; R2 = high 32 bits
        STS MACL, R3      ; R3 = low 32 bits
        XTRCT R2, R3      ; R3 = middle 32 bits (16.16 result)
        *R6 = R3          ; Store result

        Increment COMM4
        Return
    """
    code = bytearray()

    # Load addresses from literal pool
    # MOV.L @(disp,PC),Rn
    input_a_mov_offset = len(code)
    code.extend([0xD4, 0x00])  # MOV.L @(disp,PC),R4 - input_A addr

    input_b_mov_offset = len(code)
    code.extend([0xD5, 0x00])  # MOV.L @(disp,PC),R5 - input_B addr

    output_mov_offset = len(code)
    code.extend([0xD6, 0x00])  # MOV.L @(disp,PC),R6 - output addr

    # Load values
    code.extend([0x60, 0x42])  # MOV.L @R4,R0 - R0 = A
    code.extend([0x61, 0x52])  # MOV.L @R5,R1 - R1 = B

    # 32x32 signed multiply → 64-bit result in MACH:MACL
    # DMULS.L Rm,Rn: opcode 0011nnnnmmmm1101
    # DMULS.L R0,R1: 0011 0001 0000 1101 = 0x310D
    code.extend([0x31, 0x0D])  # DMULS.L R0,R1

    # Get result from MAC registers
    # STS MACH,Rn: 0000nnnn00001010
    # STS MACL,Rn: 0000nnnn00011010
    code.extend([0x02, 0x0A])  # STS MACH,R2
    code.extend([0x03, 0x1A])  # STS MACL,R3

    # Extract middle 32 bits (bits 47:16 of 64-bit result)
    # XTRCT Rm,Rn: 0010nnnnmmmm1101
    # XTRCT R2,R3: 0010 0011 0010 1101 = 0x232D
    code.extend([0x23, 0x2D])  # XTRCT R2,R3 - R3 = result

    # Store result
    code.extend([0x26, 0x32])  # MOV.L R3,@R6

    # Increment COMM4
    comm4_mov_offset = len(code)
    code.extend([0xD0, 0x00])  # MOV.L @(disp,PC),R0 - COMM4 addr

    code.extend([0x61, 0x02])  # MOV.L @R0,R1 - read COMM4
    code.extend([0x71, 0x01])  # ADD #1,R1
    code.extend([0x20, 0x12])  # MOV.L R1,@R0 - write COMM4

    # Return
    code.extend([0x00, 0x0B])  # RTS
    code.extend([0x00, 0x09])  # NOP (delay slot)

    # Align to 4 bytes
    while len(code) % 4 != 0:
        code.extend([0x00, 0x09])

    # Literal pool
    input_a_literal_offset = len(code)
    code.extend(struct.pack('>I', INPUT_A_ADDR))

    input_b_literal_offset = len(code)
    code.extend(struct.pack('>I', INPUT_B_ADDR))

    output_literal_offset = len(code)
    code.extend(struct.pack('>I', OUTPUT_ADDR))

    comm4_literal_offset = len(code)
    code.extend(struct.pack('>I', COMM4_ADDR))

    # Fix up displacements
    def calc_disp(instr_offset, literal_offset):
        pc = handler_addr + instr_offset
        base = (pc & ~3) + 4
        return (handler_addr + literal_offset - base) // 4

    code[input_a_mov_offset + 1] = calc_disp(input_a_mov_offset, input_a_literal_offset)
    code[input_b_mov_offset + 1] = calc_disp(input_b_mov_offset, input_b_literal_offset)
    code[output_mov_offset + 1] = calc_disp(output_mov_offset, output_literal_offset)
    code[comm4_mov_offset + 1] = calc_disp(comm4_mov_offset, comm4_literal_offset)

    return bytes(code)


def create_multiply_vblank_code(code_start_addr: int) -> bytes:
    """
    Create VBlank code that sets up multiply test values.

    1. Poll VBlank (original)
    2. Increment FPS counter
    3. Write VALUE_A to INPUT_A_ADDR
    4. Write VALUE_B to INPUT_B_ADDR
    5. Signal Slave via COMM6 = 0x0012
    """
    code = bytearray()

    # === VBlank poll ===
    vdp_mov_offset = len(code)
    code.extend([0xD1, 0x00])  # MOV.L @(disp,PC),R1 - VDP base

    poll_loop_offset = len(code)
    code.extend([0x85, 0x15])  # MOV.W @(10,R1),R0 - read VDP status
    code.extend([0xC8, 0x02])  # TST #2,R0 - test VBlank bit

    bf_offset = len(code)
    bf_disp = (poll_loop_offset - (bf_offset + 4)) // 2
    code.extend([0x8B, bf_disp & 0xFF])  # BF poll_loop

    # === Save registers ===
    code.extend([0x2F, 0x06])  # MOV.L R0,@-R15 (push R0)
    code.extend([0x2F, 0x26])  # MOV.L R2,@-R15 (push R2)
    code.extend([0x2F, 0x36])  # MOV.L R3,@-R15 (push R3)

    # === FPS counter ===
    counter_mov_offset = len(code)
    code.extend([0xD2, 0x00])  # MOV.L @(disp,PC),R2 - counter addr

    code.extend([0x60, 0x22])  # MOV.L @R2,R0
    code.extend([0x70, 0x01])  # ADD #1,R0
    code.extend([0x22, 0x02])  # MOV.L R0,@R2

    # === Write test values ===
    # Load input_A address and write VALUE_A
    input_a_addr_mov_offset = len(code)
    code.extend([0xD2, 0x00])  # MOV.L @(disp,PC),R2 - input_A addr

    value_a_mov_offset = len(code)
    code.extend([0xD0, 0x00])  # MOV.L @(disp,PC),R0 - VALUE_A

    code.extend([0x22, 0x02])  # MOV.L R0,@R2 - write A

    # Load input_B address and write VALUE_B
    input_b_addr_mov_offset = len(code)
    code.extend([0xD2, 0x00])  # MOV.L @(disp,PC),R2 - input_B addr

    value_b_mov_offset = len(code)
    code.extend([0xD0, 0x00])  # MOV.L @(disp,PC),R0 - VALUE_B

    code.extend([0x22, 0x02])  # MOV.L R0,@R2 - write B

    # === Signal Slave ===
    comm6_mov_offset = len(code)
    code.extend([0xD0, 0x00])  # MOV.L @(disp,PC),R0 - COMM6 addr

    code.extend([0xE1, 0x12])  # MOV #$12,R1
    code.extend([0x20, 0x12])  # MOV.W R1,@R0

    # === Restore and return ===
    code.extend([0x63, 0xF6])  # MOV.L @R15+,R3
    code.extend([0x62, 0xF6])  # MOV.L @R15+,R2
    code.extend([0x60, 0xF6])  # MOV.L @R15+,R0

    code.extend([0x00, 0x0B])  # RTS
    code.extend([0x00, 0x09])  # NOP

    # Align
    while len(code) % 4 != 0:
        code.extend([0x00, 0x09])

    # === Literal pool ===
    vdp_literal_offset = len(code)
    code.extend(struct.pack('>I', 0x20004100))  # VDP base

    counter_literal_offset = len(code)
    code.extend(struct.pack('>I', 0x22000100))  # FPS counter

    input_a_addr_literal_offset = len(code)
    code.extend(struct.pack('>I', INPUT_A_ADDR))

    value_a_literal_offset = len(code)
    code.extend(struct.pack('>I', VALUE_A))

    input_b_addr_literal_offset = len(code)
    code.extend(struct.pack('>I', INPUT_B_ADDR))

    value_b_literal_offset = len(code)
    code.extend(struct.pack('>I', VALUE_B))

    comm6_literal_offset = len(code)
    code.extend(struct.pack('>I', 0x2000402C))  # COMM6

    # === Fix displacements ===
    def calc_disp(instr_offset, literal_offset):
        pc = code_start_addr + instr_offset
        base = (pc & ~3) + 4
        return (code_start_addr + literal_offset - base) // 4

    code[vdp_mov_offset + 1] = calc_disp(vdp_mov_offset, vdp_literal_offset)
    code[counter_mov_offset + 1] = calc_disp(counter_mov_offset, counter_literal_offset)
    code[input_a_addr_mov_offset + 1] = calc_disp(input_a_addr_mov_offset, input_a_addr_literal_offset)
    code[value_a_mov_offset + 1] = calc_disp(value_a_mov_offset, value_a_literal_offset)
    code[input_b_addr_mov_offset + 1] = calc_disp(input_b_addr_mov_offset, input_b_addr_literal_offset)
    code[value_b_mov_offset + 1] = calc_disp(value_b_mov_offset, value_b_literal_offset)
    code[comm6_mov_offset + 1] = calc_disp(comm6_mov_offset, comm6_literal_offset)

    return bytes(code)


def inject_multiply_test(input_rom: str, output_rom: str) -> bool:
    """Inject 16.16 multiply test."""

    print("=" * 70)
    print("PHASE 15.6: SLAVE 16.16 FIXED-POINT MULTIPLY TEST")
    print("=" * 70)
    print()

    # Load ROM
    rom_path = Path(input_rom)
    if not rom_path.exists():
        print(f"ROM not found: {input_rom}")
        return False

    rom_data = bytearray(rom_path.read_bytes())
    print(f"ROM loaded: {len(rom_data):,} bytes")
    print()

    # === Inject Slave handler ===
    handler_offset = 0x300027
    handler_addr = 0x02300027

    new_handler = create_multiply_handler(handler_addr)
    print(f"Slave handler size: {len(new_handler)} bytes")
    print(f"Handler bytecode: {new_handler.hex(' ')}")
    print()

    print("Slave Handler Algorithm:")
    print("  1. Load A from 0x22000200")
    print("  2. Load B from 0x22000204")
    print("  3. DMULS.L A,B → 64-bit result in MACH:MACL")
    print("  4. XTRCT to get middle 32 bits (16.16 result)")
    print("  5. Store result to 0x22000210")
    print("  6. Increment COMM4")
    print()

    rom_data[handler_offset:handler_offset + len(new_handler)] = new_handler
    print(f"Injected handler at ROM 0x{handler_offset:06X}")
    print()

    # === Inject VBlank code ===
    vblank_offset = 0x300040
    vblank_addr = 0x02300040

    vblank_code = create_multiply_vblank_code(vblank_addr)
    print(f"VBlank code size: {len(vblank_code)} bytes")
    print()

    rom_data[vblank_offset:vblank_offset + len(vblank_code)] = vblank_code
    print(f"Injected VBlank at ROM 0x{vblank_offset:06X}")
    print()

    # Write output
    Path(output_rom).write_bytes(rom_data)
    print(f"Output: {output_rom}")
    print()

    # === Verification guide ===
    print("=" * 70)
    print("TEST VALUES (16.16 Fixed-Point)")
    print("=" * 70)
    print()
    print(f"  A = 0x{VALUE_A:08X} ({VALUE_A / 65536:.1f})")
    print(f"  B = 0x{VALUE_B:08X} ({VALUE_B / 65536:.1f})")
    print(f"  Expected A*B = 0x{EXPECTED:08X} ({EXPECTED / 65536:.1f})")
    print()

    print("=" * 70)
    print("VERIFICATION IN EMULATOR")
    print("=" * 70)
    print()
    print("Memory locations to check:")
    print(f"  0x{INPUT_A_ADDR:08X}: Input A  - should be 0x{VALUE_A:08X}")
    print(f"  0x{INPUT_B_ADDR:08X}: Input B  - should be 0x{VALUE_B:08X}")
    print(f"  0x{OUTPUT_ADDR:08X}: Output   - should be 0x{EXPECTED:08X}")
    print(f"  0x{COMM4_ADDR:08X}: COMM4    - should increment each frame")
    print()
    print("SUCCESS CRITERIA:")
    print(f"  ✅ Output (0x{OUTPUT_ADDR:08X}) = 0x{EXPECTED:08X}")
    print("  ✅ COMM4 increments steadily")
    print()
    print("This proves Slave can do 16.16 fixed-point multiply!")
    print("Next step: Matrix-vector multiplication for vertex transforms.")
    print()

    return True


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 inject_multiply_test.py <input.32x> <output.32x>")
        print()
        print("Example:")
        print("  python3 inject_multiply_test.py build/vr_baseline_probe.32x build/vr_multiply_test.32x")
        sys.exit(1)

    success = inject_multiply_test(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
