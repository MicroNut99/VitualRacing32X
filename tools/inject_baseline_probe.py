#!/usr/bin/env python3
"""
Baseline Probe Injector - FPS Counter + Master→Slave Signal

Phase 15: Establishes performance baseline and verifies end-to-end signaling.

This tool injects code at the VBlank poll function that:
1. Does the original VBlank poll (wait for frame boundary)
2. Increments the FPS counter at 0x22000100
3. Writes COMM6 = 0x0012 to signal the Slave SH2

The Slave hook (Phase 11) at 0x06000596 will:
1. Detect COMM6 = 0x0012
2. Call handler at 0x02300027
3. Increment COMM4 response counter
4. Clear COMM6

This creates a verifiable round-trip signal once per frame.

Monitor in emulator:
- 0x22000100: VBlank counter (should be ~60/sec)
- 0x20004028: COMM4 (should also be ~60/sec if signal working)
"""

import sys
import struct
from pathlib import Path


def create_vblank_with_signal(code_start_addr: int) -> bytes:
    """
    Create VBlank poll + FPS counter + Master signal code.

    This replaces the original VBlank poll function.
    Original function was at 0x243E0-0x243EF (16 bytes).
    """
    code = bytearray()

    # === Original VBlank poll logic ===
    # Load VDP base address (literal will be at end)
    # MOV.L @(disp,PC),R1
    vdp_mov_offset = len(code)
    code.extend([0xD1, 0x00])  # Placeholder - will fix

    # poll_loop:
    poll_loop_offset = len(code)
    code.extend([0x85, 0x15])  # MOV.W @(10,R1),R0 - read VDP status
    code.extend([0xC8, 0x02])  # TST #2,R0 - test VBlank bit

    # BF back to poll_loop
    bf_offset = len(code)
    bf_disp = (poll_loop_offset - (bf_offset + 4)) // 2
    if bf_disp < 0:
        bf_disp = bf_disp & 0xFF  # 8-bit signed
    code.extend([0x8B, bf_disp & 0xFF])  # BF poll_loop

    # === FPS counter increment ===
    # Save R0, R2 (R1 still has VDP base)
    code.extend([0x2F, 0x06])  # MOV.L R0,@-R15 (push R0)
    code.extend([0x2F, 0x26])  # MOV.L R2,@-R15 (push R2)

    # Load counter base address
    counter_mov_offset = len(code)
    code.extend([0xD2, 0x00])  # MOV.L @(disp,PC),R2 - placeholder

    # Increment total frame counter
    code.extend([0x60, 0x22])  # MOV.L @R2,R0
    code.extend([0x70, 0x01])  # ADD #1,R0
    code.extend([0x22, 0x02])  # MOV.L R0,@R2

    # === NEW: Master→Slave signal ===
    # Load COMM6 address
    comm6_mov_offset = len(code)
    code.extend([0xD0, 0x00])  # MOV.L @(disp,PC),R0 - placeholder (COMM6 addr)

    # Write signal value 0x0012
    code.extend([0xE1, 0x12])  # MOV #$12,R1 (load 0x12 into R1)
    code.extend([0x20, 0x12])  # MOV.W R1,@R0 (write to COMM6)

    # === Restore and return ===
    code.extend([0x62, 0xF6])  # MOV.L @R15+,R2 (pop R2)
    code.extend([0x60, 0xF6])  # MOV.L @R15+,R0 (pop R0)

    # Return
    code.extend([0x00, 0x0B])  # RTS
    code.extend([0x00, 0x09])  # NOP (delay slot)

    # Align to 4 bytes for literals
    while len(code) % 4 != 0:
        code.extend([0x00, 0x09])  # NOP padding

    # Literal pool
    vdp_literal_offset = len(code)
    code.extend(struct.pack('>I', 0x20004100))  # VDP base address

    counter_literal_offset = len(code)
    code.extend(struct.pack('>I', 0x22000100))  # FPS counter base address

    comm6_literal_offset = len(code)
    code.extend(struct.pack('>I', 0x2000402C))  # COMM6 register address

    # === Fix up MOV.L displacements ===
    # For MOV.L @(disp,PC),Rn: addr = (PC & ~3) + 4 + disp*4

    # Fix VDP MOV.L
    vdp_pc = code_start_addr + vdp_mov_offset
    vdp_base = (vdp_pc & ~3) + 4
    vdp_disp = (code_start_addr + vdp_literal_offset - vdp_base) // 4
    code[vdp_mov_offset + 1] = vdp_disp

    # Fix counter MOV.L
    counter_pc = code_start_addr + counter_mov_offset
    counter_base = (counter_pc & ~3) + 4
    counter_disp = (code_start_addr + counter_literal_offset - counter_base) // 4
    code[counter_mov_offset + 1] = counter_disp

    # Fix COMM6 MOV.L
    comm6_pc = code_start_addr + comm6_mov_offset
    comm6_base = (comm6_pc & ~3) + 4
    comm6_disp = (code_start_addr + comm6_literal_offset - comm6_base) // 4
    code[comm6_mov_offset + 1] = comm6_disp

    return bytes(code)


def inject_baseline_probe(input_rom: str, output_rom: str) -> bool:
    """Inject baseline probe (FPS counter + Master signal)."""

    print("=" * 70)
    print("BASELINE PROBE INJECTOR - FPS Counter + Master Signal")
    print("=" * 70)
    print()

    # Load ROM
    rom_path = Path(input_rom)
    if not rom_path.exists():
        print(f"ROM not found: {input_rom}")
        return False

    rom_data = bytearray(rom_path.read_bytes())
    print(f"ROM loaded: {len(rom_data):,} bytes")

    # Find VBlank poll function
    # Pattern: D102 8515 C802 8BFC 000B 0009
    pattern = bytes([0xD1, 0x02, 0x85, 0x15, 0xC8, 0x02, 0x8B, 0xFC, 0x00, 0x0B, 0x00, 0x09])

    vblank_func = None
    for i in range(0x20000, len(rom_data) - len(pattern)):
        if rom_data[i:i+len(pattern)] == pattern:
            vblank_func = i
            break

    if vblank_func is None:
        print("VBlank poll function not found!")
        return False

    print(f"VBlank function found at ROM 0x{vblank_func:06X}")
    print(f"  SH2 address: 0x{0x02000000 + vblank_func:08X}")
    print()

    # Find free space in expansion ROM area (0x300000+)
    # Phase 12 handler is at 0x300027, so start after 0x300040
    code_size = 64
    free_space = 0x300040  # After Phase 12 handler

    # Verify it's all 0xFF (erased)
    if not all(b == 0xFF for b in rom_data[free_space:free_space+code_size]):
        print(f"Warning: Space at 0x{free_space:06X} not empty, looking for alternative...")
        for i in range(0x300040, len(rom_data) - code_size, 4):
            if all(b == 0xFF for b in rom_data[i:i+code_size]):
                free_space = i
                break
        else:
            print("No free space found!")
            return False

    print(f"Free space found at ROM 0x{free_space:06X}")

    # CPU address for the new code
    new_code_addr = 0x02000000 + free_space
    print(f"New code CPU address: 0x{new_code_addr:08X}")
    print()

    # Generate the combined code
    new_code = create_vblank_with_signal(new_code_addr)
    print(f"New code size: {len(new_code)} bytes")
    print(f"New code hex: {new_code.hex(' ')}")
    print()

    # Inject new code
    rom_data[free_space:free_space+len(new_code)] = new_code
    print(f"Injected new code at ROM 0x{free_space:06X}")

    # Replace original function with JMP to new code
    # D101  MOV.L @(4,PC),R1   ; Load new code address
    # 412B  JMP @R1            ; Jump to new code
    # 0009  NOP                ; Delay slot
    # 0009  NOP                ; Padding
    # xxxx  Literal            ; New code address

    replacement = bytearray()
    replacement.extend([0xD1, 0x01])  # MOV.L @(4,PC),R1
    replacement.extend([0x41, 0x2B])  # JMP @R1
    replacement.extend([0x00, 0x09])  # NOP (delay slot)
    replacement.extend([0x00, 0x09])  # NOP (padding)
    replacement.extend(struct.pack('>I', new_code_addr))  # Literal
    # Fill rest with NOPs
    while len(replacement) < 16:
        replacement.extend([0x00, 0x09])

    print(f"Replacement code: {replacement.hex(' ')}")
    print()

    rom_data[vblank_func:vblank_func+16] = replacement
    print(f"Replaced original function at ROM 0x{vblank_func:06X}")
    print()

    # Write output
    Path(output_rom).write_bytes(rom_data)
    print(f"Output written: {output_rom}")
    print()

    # Summary
    print("=" * 70)
    print("INJECTION SUMMARY")
    print("=" * 70)
    print()
    print("What was injected:")
    print("  1. VBlank poll (original logic preserved)")
    print("  2. FPS counter increment at 0x22000100")
    print("  3. Master→Slave signal: COMM6 ← 0x0012")
    print()
    print("Monitor in emulator:")
    print("  0x22000100  VBlank counter (should increment ~60/sec)")
    print("  0x20004028  COMM4 (should increment ~60/sec if signal working)")
    print("  0x2000402C  COMM6 (should flash 0x0012 → 0x0000 each frame)")
    print()
    print("Success criteria:")
    print("  - ROM boots without crash")
    print("  - VBlank counter (0x22000100) increments steadily")
    print("  - COMM4 (0x20004028) increments at same rate (signal verified!)")
    print()
    print("=" * 70)

    return True


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 inject_baseline_probe.py <input.32x> <output.32x>")
        print()
        print("Example:")
        print("  python3 inject_baseline_probe.py build/vr_rebuild.32x build/vr_baseline_probe.32x")
        sys.exit(1)

    success = inject_baseline_probe(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
