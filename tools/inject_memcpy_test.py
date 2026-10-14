#!/usr/bin/env python3
"""
Phase 15.5: Slave Memory Copy Test

Replaces the Slave handler with a memory copy test:
1. Copies 16 bytes from source to destination in SDRAM
2. Increments COMM4 (for verification that handler ran)
3. Returns to hook

Also updates the Master VBlank code to write a test pattern before signaling.

Test setup:
- Source: 0x22000200 (initialized with test pattern by Master every frame)
- Destination: 0x22000210 (should contain copied data after handler runs)
- COMM4: Should increment each frame (proves handler executed)

Usage:
    python3 tools/inject_memcpy_test.py build/vr_baseline_probe.32x build/vr_memcpy_test.32x
"""

import sys
import struct
from pathlib import Path

# Test pattern: DEADBEEF CAFEBABE 12345678 ABCDEF00
TEST_PATTERN = [0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF00]
SOURCE_ADDR = 0x22000200
DEST_ADDR = 0x22000210


def create_memcpy_handler(handler_addr: int) -> bytes:
    """
    Create SH2 handler that copies 16 bytes and increments COMM4.

    Handler logic:
        R4 = source address (0x22000200)
        R5 = destination address (0x22000210)
        R3 = loop counter (4 iterations for 16 bytes)

        loop:
            R0 = *R4++      ; Read longword
            *R5 = R0        ; Write to dest
            R5 += 4         ; Advance dest
            if (--R3 != 0) goto loop

        R0 = &COMM4
        R1 = *R0
        R1++
        *R0 = R1
        RTS
    """
    code = bytearray()

    # We'll place literals at the end, calculate offsets later
    # Code structure:
    #   0x00: MOV.L @(lit1,PC),R4   ; Load source address
    #   0x02: MOV.L @(lit2,PC),R5   ; Load dest address
    #   0x04: MOV #4,R3             ; Loop counter
    # loop:
    #   0x06: MOV.L @R4+,R0         ; Read from source (auto-inc)
    #   0x08: MOV.L R0,@R5          ; Write to dest
    #   0x0A: ADD #4,R5             ; Advance dest pointer
    #   0x0C: DT R3                 ; Decrement and test
    #   0x0E: BF loop               ; Loop back if not zero
    #   0x10: MOV.L @(lit3,PC),R0   ; Load COMM4 address
    #   0x12: MOV.L @R0,R1          ; Read COMM4
    #   0x14: ADD #1,R1             ; Increment
    #   0x16: MOV.L R1,@R0          ; Write back
    #   0x18: RTS                   ; Return
    #   0x1A: NOP                   ; Delay slot
    #   0x1C: (align)
    # literals:
    #   0x1C: source_addr (0x22000200)
    #   0x20: dest_addr (0x22000210)
    #   0x24: comm4_addr (0x20004028)

    # Calculate PC-relative displacements
    # For MOV.L @(disp,PC),Rn: addr = (PC & ~3) + 4 + disp*4
    # PC is address of the instruction

    # Instruction 0 at handler_addr + 0x00: MOV.L @(lit1,PC),R4
    # Literal 1 at handler_addr + 0x1C
    # PC = handler_addr + 0x00
    # (PC & ~3) + 4 = handler_addr + 4 (assuming handler_addr is aligned)
    # We need: handler_addr + 4 + disp*4 = handler_addr + 0x1C
    # disp*4 = 0x1C - 4 = 0x18
    # disp = 6
    lit1_disp = 6

    # Instruction 1 at handler_addr + 0x02: MOV.L @(lit2,PC),R5
    # Literal 2 at handler_addr + 0x20
    # PC = handler_addr + 0x02
    # (PC & ~3) + 4 = handler_addr + 4
    # We need: handler_addr + 4 + disp*4 = handler_addr + 0x20
    # disp*4 = 0x20 - 4 = 0x1C
    # disp = 7
    lit2_disp = 7

    # Instruction at handler_addr + 0x10: MOV.L @(lit3,PC),R0
    # Literal 3 at handler_addr + 0x24
    # PC = handler_addr + 0x10
    # (PC & ~3) + 4 = handler_addr + 0x10 + 4 = handler_addr + 0x14
    # We need: handler_addr + 0x14 + disp*4 = handler_addr + 0x24
    # disp*4 = 0x24 - 0x14 = 0x10
    # disp = 4
    lit3_disp = 4

    # Build the code
    # MOV.L @(6,PC),R4 - opcode: D4nn where nn = disp
    code.extend([0xD4, lit1_disp])

    # MOV.L @(7,PC),R5 - opcode: D5nn
    code.extend([0xD5, lit2_disp])

    # MOV #4,R3 - opcode: E3nn where nn = immediate
    code.extend([0xE3, 0x04])

    # loop (at offset 0x06):
    # MOV.L @R4+,R0 - opcode: 6046
    code.extend([0x60, 0x46])

    # MOV.L R0,@R5 - opcode: 2502
    code.extend([0x25, 0x02])

    # ADD #4,R5 - opcode: 75nn
    code.extend([0x75, 0x04])

    # DT R3 - opcode: 4310
    code.extend([0x43, 0x10])

    # BF loop - branch back to offset 0x06
    # Current position: 0x0E, target: 0x06
    # BF displacement: target = PC + 4 + disp*2
    # PC = 0x0E, target = 0x06
    # 0x06 = 0x0E + 4 + disp*2 = 0x12 + disp*2
    # disp*2 = 0x06 - 0x12 = -0x0C = -12
    # disp = -6
    bf_disp = (-6) & 0xFF  # 8-bit signed as unsigned
    code.extend([0x8B, bf_disp])

    # MOV.L @(4,PC),R0 - opcode: D0nn
    code.extend([0xD0, lit3_disp])

    # MOV.L @R0,R1 - opcode: 6102
    code.extend([0x61, 0x02])

    # ADD #1,R1 - opcode: 71nn
    code.extend([0x71, 0x01])

    # MOV.L R1,@R0 - opcode: 2012
    code.extend([0x20, 0x12])

    # RTS - opcode: 000B
    code.extend([0x00, 0x0B])

    # NOP (delay slot) - opcode: 0009
    code.extend([0x00, 0x09])

    # Align to 4 bytes for literals (current size should be 0x1C = 28 bytes)
    while len(code) % 4 != 0:
        code.extend([0x00, 0x09])  # NOP padding

    # Literal pool
    code.extend(struct.pack('>I', 0x22000200))  # Source address
    code.extend(struct.pack('>I', 0x22000210))  # Destination address
    code.extend(struct.pack('>I', 0x20004028))  # COMM4 address

    return bytes(code)


def create_master_init_pattern(pattern_addr: int) -> bytes:
    """
    Create SH2 code to initialize the test pattern at source address.

    This should be called once to set up the test data.
    Writes 0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF00 to 0x22000200.
    """
    code = bytearray()

    # This code will be added to the Master's VBlank handler
    # to initialize the source memory once

    # We'll use a simple approach: write known values
    # R2 = destination (0x22000200)
    # Write 4 longwords

    # MOV.L @(disp,PC),R2 - load address
    # Literal at end of code

    # For now, we'll handle this differently -
    # inject initialization code into the baseline probe

    return bytes(code)


def create_extended_vblank_code(code_start_addr: int) -> bytes:
    """
    Create extended VBlank code that:
    1. Polls VBlank (original)
    2. Increments FPS counter (original)
    3. Writes test pattern to 0x22000200 (NEW)
    4. Signals COMM6 = 0x0012 (original)
    5. Returns
    """
    code = bytearray()

    # === Original VBlank poll logic ===
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

    # === FPS counter increment ===
    counter_mov_offset = len(code)
    code.extend([0xD2, 0x00])  # MOV.L @(disp,PC),R2 - counter addr

    code.extend([0x60, 0x22])  # MOV.L @R2,R0
    code.extend([0x70, 0x01])  # ADD #1,R0
    code.extend([0x22, 0x02])  # MOV.L R0,@R2

    # === NEW: Write test pattern to 0x22000200 ===
    pattern_addr_mov_offset = len(code)
    code.extend([0xD2, 0x00])  # MOV.L @(disp,PC),R2 - pattern dest addr

    # Write 4 longwords (pattern values stored in literals)
    pattern_lit_offsets = []
    for i in range(4):
        pattern_lit_offsets.append(len(code))
        code.extend([0xD0, 0x00])  # MOV.L @(disp,PC),R0 - load pattern word
        code.extend([0x22, 0x02])  # MOV.L R0,@R2 - write to dest
        code.extend([0x72, 0x04])  # ADD #4,R2 - advance pointer

    # === Master→Slave signal ===
    comm6_mov_offset = len(code)
    code.extend([0xD0, 0x00])  # MOV.L @(disp,PC),R0 - COMM6 addr

    code.extend([0xE1, 0x12])  # MOV #$12,R1
    code.extend([0x20, 0x12])  # MOV.W R1,@R0

    # === Restore and return ===
    code.extend([0x63, 0xF6])  # MOV.L @R15+,R3 (pop R3)
    code.extend([0x62, 0xF6])  # MOV.L @R15+,R2 (pop R2)
    code.extend([0x60, 0xF6])  # MOV.L @R15+,R0 (pop R0)

    code.extend([0x00, 0x0B])  # RTS
    code.extend([0x00, 0x09])  # NOP (delay slot)

    # Align to 4 bytes for literals
    while len(code) % 4 != 0:
        code.extend([0x00, 0x09])

    # === Literal pool ===
    vdp_literal_offset = len(code)
    code.extend(struct.pack('>I', 0x20004100))  # VDP base

    counter_literal_offset = len(code)
    code.extend(struct.pack('>I', 0x22000100))  # FPS counter

    pattern_addr_literal_offset = len(code)
    code.extend(struct.pack('>I', SOURCE_ADDR))  # Pattern dest (0x22000200)

    pattern_value_offsets = []
    for val in TEST_PATTERN:
        pattern_value_offsets.append(len(code))
        code.extend(struct.pack('>I', val))

    comm6_literal_offset = len(code)
    code.extend(struct.pack('>I', 0x2000402C))  # COMM6

    # === Fix up displacements ===
    def calc_disp(instr_offset, literal_offset):
        pc = code_start_addr + instr_offset
        base = (pc & ~3) + 4
        return (code_start_addr + literal_offset - base) // 4

    code[vdp_mov_offset + 1] = calc_disp(vdp_mov_offset, vdp_literal_offset)
    code[counter_mov_offset + 1] = calc_disp(counter_mov_offset, counter_literal_offset)
    code[pattern_addr_mov_offset + 1] = calc_disp(pattern_addr_mov_offset, pattern_addr_literal_offset)
    code[comm6_mov_offset + 1] = calc_disp(comm6_mov_offset, comm6_literal_offset)

    # Fix pattern value loads
    for i, offset in enumerate(pattern_lit_offsets):
        code[offset + 1] = calc_disp(offset, pattern_value_offsets[i])

    return bytes(code)


def inject_memcpy_test(input_rom: str, output_rom: str) -> bool:
    """Inject memory copy test handler and pattern initialization."""

    print("=" * 70)
    print("PHASE 15.5: SLAVE MEMORY COPY TEST")
    print("=" * 70)
    print()

    # Load ROM
    rom_path = Path(input_rom)
    if not rom_path.exists():
        print(f"ROM not found: {input_rom}")
        return False

    rom_data = bytearray(rom_path.read_bytes())
    print(f"ROM loaded: {len(rom_data):,} bytes")

    # === PART 1: Inject Slave handler ===
    handler_offset = 0x300027  # File offset
    handler_addr = 0x02300027  # SH2 address

    print(f"Handler location: ROM 0x{handler_offset:06X} (SH2 0x{handler_addr:08X})")

    new_handler = create_memcpy_handler(handler_addr)
    print(f"New handler size: {len(new_handler)} bytes")
    print(f"Handler bytecode: {new_handler.hex(' ')}")
    print()

    print("Slave Handler disassembly:")
    print("  0x00: D406      MOV.L   @(6,PC),R4    ; R4 = source (0x22000200)")
    print("  0x02: D507      MOV.L   @(7,PC),R5    ; R5 = dest (0x22000210)")
    print("  0x04: E304      MOV     #4,R3         ; R3 = loop counter")
    print("  loop:")
    print("  0x06: 6046      MOV.L   @R4+,R0       ; Read from source")
    print("  0x08: 2502      MOV.L   R0,@R5        ; Write to dest")
    print("  0x0A: 7504      ADD     #4,R5         ; Advance dest")
    print("  0x0C: 4310      DT      R3            ; Decrement counter")
    print("  0x0E: 8BFA      BF      loop          ; Loop if not zero")
    print("  0x10: D004      MOV.L   @(4,PC),R0    ; R0 = &COMM4")
    print("  0x12: 6102      MOV.L   @R0,R1        ; Read COMM4")
    print("  0x14: 7101      ADD     #1,R1         ; Increment")
    print("  0x16: 2012      MOV.L   R1,@R0        ; Write back")
    print("  0x18: 000B      RTS")
    print("  0x1A: 0009      NOP")
    print()

    rom_data[handler_offset:handler_offset + len(new_handler)] = new_handler
    print(f"Injected Slave handler at ROM 0x{handler_offset:06X}")
    print()

    # === PART 2: Update Master VBlank to write test pattern ===
    print("=" * 70)
    print("MASTER VBLANK UPDATE")
    print("=" * 70)
    print()

    vblank_probe_offset = 0x300040
    vblank_probe_addr = 0x02300040

    if rom_data[vblank_probe_offset] == 0xFF:
        print("WARNING: Baseline probe not found at 0x300040")
        print("         Run inject_baseline_probe.py first!")
        print("         Or manually set test pattern in emulator.")
    else:
        # Generate extended VBlank code
        extended_vblank = create_extended_vblank_code(vblank_probe_addr)
        print(f"Extended VBlank code size: {len(extended_vblank)} bytes")
        print(f"Extended VBlank hex: {extended_vblank.hex(' ')}")
        print()

        print("Master VBlank now does:")
        print(f"  1. Poll VBlank (original)")
        print(f"  2. Increment FPS counter at 0x22000100")
        print(f"  3. Write test pattern to 0x{SOURCE_ADDR:08X}:")
        for i, val in enumerate(TEST_PATTERN):
            print(f"       +{i*4:02X}: 0x{val:08X}")
        print(f"  4. Signal Slave via COMM6 = 0x0012")
        print()

        rom_data[vblank_probe_offset:vblank_probe_offset + len(extended_vblank)] = extended_vblank
        print(f"Injected extended VBlank at ROM 0x{vblank_probe_offset:06X}")

    # Write output
    Path(output_rom).write_bytes(rom_data)
    print()
    print(f"Output written: {output_rom}")
    print()

    print("=" * 70)
    print("VERIFICATION")
    print("=" * 70)
    print()
    print("The test is now FULLY AUTOMATIC. In emulator memory viewer:")
    print()
    print(f"1. Source (0x{SOURCE_ADDR:08X}): Should contain test pattern")
    for i, val in enumerate(TEST_PATTERN):
        print(f"      +{i*4:02X}: 0x{val:08X}")
    print()
    print(f"2. Destination (0x{DEST_ADDR:08X}): Should be IDENTICAL after first frame")
    print()
    print("3. COMM4 (0x20004028): Should increment each frame")
    print()
    print("SUCCESS CRITERIA:")
    print(f"   ✅ 0x{DEST_ADDR:08X} matches 0x{SOURCE_ADDR:08X} → Slave copy works!")
    print("   ✅ COMM4 increments each frame → Handler executing!")
    print()
    print("FAILURE DIAGNOSIS:")
    print(f"   - Dest is 0x00000000 but COMM4 increments → Copy failed (address issue)")
    print(f"   - COMM4 doesn't increment → Handler not being called")
    print(f"   - Source is 0x00000000 → Master pattern write failed")
    print()

    return True


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 inject_memcpy_test.py <input.32x> <output.32x>")
        print()
        print("Example:")
        print("  python3 tools/inject_memcpy_test.py build/vr_baseline_probe.32x build/vr_memcpy_test.32x")
        sys.exit(1)

    success = inject_memcpy_test(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
