#!/usr/bin/env python3
"""
SH2 Frame Counter Injector for Virtua Racing Deluxe

Injects a frame counter that increments at the SH2 frame completion point
(final_exit at CPU address 0x0222399A, ROM offset 0x23A9A).

This allows measuring actual SH2 frame rate (not Mega Drive V-INT rate).
Expected: ~20 FPS baseline in gameplay, heavily fluctuating.
Benchmark: Total frames rendered in 60 real-time seconds.

Memory locations:
- SH2 frame counter: SDRAM 0x22000400 (long word, 4 bytes)
  - CPU address range: 0x22000000-0x223FFFFF
  - Access from SH2 cache: 0x02000400
  - Access from 68K: 0xA02000 area (if visible)
"""

import struct
from pathlib import Path


def create_sh2_frame_counter_hook(code_addr: int) -> bytes:
    """
    Create SH2 code that counts frames and provides visual feedback.

    This is called at frame completion (0x0222399A) in the 3D rendering pipeline.

    The code does TWO things:
    1. Increments counter at 0x22000400 (for benchmarking)
    2. Writes to palette entry #0 (for visual verification)

    Why palette feedback? The palette color will cycle as frames increment,
    giving visual proof that the SH2 code is running and counting.

    Code is position-independent and minimal (24 bytes total).
    """
    code = bytearray()
    
    def add_word(val):
        code.extend(struct.pack('>H', val))
    
    # === SH2 Frame Counter + Palette Visual Feedback ===
    # Increments counter at 0x22000400
    # Also writes changing color to palette entry #1 for visual feedback

    # Load counter address: MOV.L @(disp,PC),R0
    add_word(0xC70E)  # MOV.L @(14,PC),R0  ; Load counter addr from literal

    # Load current counter: MOV.L @R0,R1
    add_word(0x6062)  # MOV.L @R0,R1

    # Increment: ADD #1,R1
    add_word(0x7101)  # ADD #1,R1

    # Store back: MOV.L R1,@R0
    add_word(0x2012)  # MOV.L R1,@R0

    # === Write to Palette for Visual Feedback ===
    # Load palette base address: MOV.L @(disp,PC),R2
    add_word(0xCA0A)  # MOV.L @(10,PC),R2  ; Load palette addr from literal

    # Copy frame count to R3: MOV.W R1,R3
    add_word(0x6310)  # MOV.W R1,R3

    # Write color to palette entry 0: MOV.W R3,@R2
    add_word(0x2032)  # MOV.W R3,@R2

    # Return from subroutine
    add_word(0x000B)  # RTS
    add_word(0x0009)  # NOP (delay slot)

    # === Literal Pool ===
    counter_addr = 0x22000400    # Frame counter location
    palette_addr = 0x22004200    # Palette base (entry 0)

    add_word((counter_addr >> 16) & 0xFFFF)
    add_word(counter_addr & 0xFFFF)
    add_word((palette_addr >> 16) & 0xFFFF)
    add_word(palette_addr & 0xFFFF)

    return bytes(code)


def inject_sh2_frame_counter(input_rom: str, output_rom: str) -> bool:
    """Inject SH2 frame counter at final_exit (0x0222399A)."""
    
    print("=" * 70)
    print("SH2 FRAME COUNTER INJECTOR")
    print("=" * 70)
    print()
    
    # Load ROM
    rom_path = Path(input_rom)
    if not rom_path.exists():
        print(f"ERROR: ROM not found: {input_rom}")
        return False
    
    rom_data = bytearray(rom_path.read_bytes())
    print(f"ROM loaded: {len(rom_data):,} bytes")
    
    # SH2 final_exit location
    # CPU address: 0x0222399A
    # ROM offset: 0x0222399A - 0x02000000 = 0x023A9A
    FINAL_EXIT_ROM_OFFSET = 0x023A9A
    
    print(f"Target hook location (ROM): 0x{FINAL_EXIT_ROM_OFFSET:06X}")
    print(f"Target hook location (CPU): 0x0222399A")
    print()
    
    # Verify we can read the expected code at that location
    # At 0x023A9A, we should have the final_exit sequence
    # Expected: various MOV.B operations ending with RTS
    
    expected_bytes = rom_data[FINAL_EXIT_ROM_OFFSET:FINAL_EXIT_ROM_OFFSET+16]
    print(f"Bytes at hook location:")
    print(f"  {expected_bytes.hex(' ')}")
    print()
    
    # Create frame counter code
    frame_counter_code = create_sh2_frame_counter_hook(0x0222399A)
    print(f"Frame counter code size: {len(frame_counter_code)} bytes")
    print(f"Code hex: {frame_counter_code.hex()}")
    print()
    
    # Strategy: Replace one instruction at final_exit with JSR to our code
    # We need to find free space to put our code, then replace an instruction
    # with a JSR that calls it
    
    # Find free space (FF FF FF FF pattern)
    free_space = None
    for i in range(0x20000, len(rom_data) - len(frame_counter_code) - 4, 4):
        if all(b == 0xFF for b in rom_data[i:i+len(frame_counter_code)]):
            free_space = i
            break
    
    if free_space is None:
        print("ERROR: No free space found for frame counter code")
        return False
    
    print(f"Free space found at ROM offset: 0x{free_space:06X}")
    
    # Calculate CPU address for free space
    # ROM offset -> CPU address for SH2: add 0x02000000
    code_cpu_addr = free_space + 0x02000000
    print(f"Code CPU address: 0x{code_cpu_addr:08X}")
    print()
    
    # Inject the frame counter code
    rom_data[free_space:free_space+len(frame_counter_code)] = frame_counter_code
    print(f"Injected frame counter code at 0x{free_space:06X}")
    
    # Now we need to hook it at final_exit
    # We'll insert a JSR (Jump to Subroutine) to our frame counter code
    # JSR @Rn is a 2-byte instruction: 0x4E0n where n=register
    # But we need to load the address first, so use:
    # MOV.L @(disp,PC),Rn followed by JSR @Rn

    # At ROM 0x023A9A (final_exit), we can replace some instructions
    # Looking at the code, there's space to work with
    # We'll insert: MOV.L (pc+relative)->R0, then JSR @R0

    # Find space near final_exit to put a jump stub (within branch range)
    # We need just 8 bytes for the stub
    stub_space = None
    for i in range(max(FINAL_EXIT_ROM_OFFSET - 0x200, 0),
                   min(FINAL_EXIT_ROM_OFFSET + 0x200, len(rom_data) - 8), 2):
        if all(b == 0xFF for b in rom_data[i:i+8]):
            stub_space = i
            break

    if stub_space is None:
        print("WARNING: No nearby free space for jump stub")
        print("         Proceeding without hook installation")
    else:
        # Create jump stub at stub_space
        # BRA stub_space (branch to our stub code)
        stub_code = bytearray()

        # We'll put the stub in the free space
        # MOV.L @(4,PC),R0   ; Load counter code address
        stub_code.extend([0xC7, 0x01])

        # JSR @R0            ; Jump to counter code
        stub_code.extend([0x40, 0x0B])

        # NOP (delay slot)
        stub_code.extend([0x00, 0x09])

        # NOP (padding)
        stub_code.extend([0x00, 0x09])

        # Literal: address of frame counter code
        stub_code.extend(struct.pack('>I', code_cpu_addr))

        # Inject stub
        rom_data[stub_space:stub_space+len(stub_code)] = stub_code
        stub_cpu_addr = stub_space + 0x02000000

        print(f"Jump stub created at ROM 0x{stub_space:06X}")
        print(f"Jump stub CPU address: 0x{stub_cpu_addr:08X}")

        # Now replace an instruction at final_exit with BRA to our stub
        # We need to calculate the branch offset
        # BRA.W offset: PC = current address + 4, target = PC + offset*2
        # For a 16-bit BRA: offset range is ±32KB

        bra_from = FINAL_EXIT_ROM_OFFSET
        bra_to = stub_space
        offset = (bra_to - (bra_from + 4)) // 2

        if -32768 <= offset <= 32767:
            # Create BRA.W instruction
            bra_instr = struct.pack('>HH', 0xA000 | (offset & 0xFFFF), 0x0000)
            rom_data[bra_from:bra_from+4] = bra_instr
            print(f"Installed BRA from 0x{bra_from:06X} to stub at 0x{stub_space:06X}")
            print(f"Branch offset: {offset} words")
        else:
            print(f"WARNING: Branch offset {offset} out of range")

    print()
    print("=" * 70)
    print("INJECTION COMPLETE")
    print("=" * 70)
    print()
    print(f"""
Frame Counter Details:
  Storage location: SDRAM 0x22000400 (32-bit word)

  Visual Feedback: Palette entry #0 cycles through colors
  (Color changes with each frame as counter increments)
  Expected: Smooth color cycling at ~20 FPS (baseline)

Benchmark Method:
  1. Visual confirmation: Watch palette color cycle
  2. If color cycles smoothly: SH2 code is working!
  3. If color is static: Hook not installed correctly
  4. Frame rate = how fast the palette cycles
     ~20 Hz baseline = color cycles 20 times per second

Manual 60-Second Benchmark:
  1. Note the value at 0x22000400 at start (if accessible)
  2. Play for exactly 60 seconds
  3. Note the value at end
  4. Difference = total SH2 frames rendered
  5. Expected baseline: ~1200 frames

Frame Counter Code Location:
  ROM offset: 0x{free_space:06X}
  CPU address: 0x{code_cpu_addr:08X}
  Size: {len(frame_counter_code)} bytes

Hook Installation:
  - Entry point (final_exit): ROM 0x{FINAL_EXIT_ROM_OFFSET:06X}
  - Frame counter code: ROM 0x{free_space:06X}
""")

    # Write output
    Path(output_rom).write_bytes(rom_data)
    print(f"Output written: {output_rom}")

    hook_status = "INSTALLED" if stub_space else "NOT INSTALLED (no nearby free space)"
    print(f"Hook status: {hook_status}")
    print()

    if not stub_space:
        print("""
NOTE: The frame counter code is in ROM, but the hook was not automatically
installed because no nearby free space was found. The hook must be manually
installed by modifying the final_exit code at ROM 0x023A9A to call the
frame counter code at 0x0202DD5C.

Alternatively, you can run this in "manual benchmark mode":
1. Load the ROM
2. Zero out memory at 0x22000400 (frame counter location)
3. Run your test for exactly 60 seconds
4. Read the value at 0x22000400 - that's your frame count
""")

    return True


def main():
    import sys
    if len(sys.argv) != 3:
        print("Usage: python3 inject_sh2_frame_counter.py <input.32x> <output.32x>")
        sys.exit(1)
    
    success = inject_sh2_frame_counter(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
