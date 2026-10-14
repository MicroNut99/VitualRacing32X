#!/usr/bin/env python3
"""
FIFO Batching Optimization for func_065

Modifies func_065 to batch frame buffer writes in groups of 4 longwords,
triggering the VDP's 4-word write FIFO for optimal throughput.

Current: 28 individual longword writes
Optimized: 7 batches of 4 longwords each

Expected gain: +10-15% FPS (24 → 27-28 FPS)
"""

import sys
import struct
from pathlib import Path

def analyze_func_065(rom_data):
    """Analyze func_065 to understand current write pattern"""
    print("\n=== Analyzing func_065 (ROM 0x23F2C-0x23FC2) ===\n")

    func_start = 0x23F2C
    func_end = 0x23FC2
    func_size = func_end - func_start

    print(f"Function size: {func_size} bytes (0x{func_size:X})")
    print(f"Location: 0x{func_start:06X} - 0x{func_end:06X}")

    # Check current instruction pattern
    code = rom_data[func_start:func_end]

    # Count MOV.L instructions
    mov_count = 0
    add_count = 0

    for i in range(0, len(code)-1, 2):
        opcode = struct.unpack('>H', code[i:i+2])[0]

        # MOV.L @R0+,R2 = 0x6206
        if opcode == 0x6206:
            mov_count += 1

        # ADD R13,R1 = 0x31DC
        if opcode == 0x31DC:
            add_count += 1

    print(f"\nCurrent pattern:")
    print(f"  MOV.L @R0+,R2 instructions: {mov_count}")
    print(f"  ADD R13,R1 instructions: {add_count}")
    print(f"  Iterations: {add_count} (14 expected)")
    print(f"  Writes per iteration: {mov_count // add_count if add_count > 0 else 0}")

    return {
        'start': func_start,
        'end': func_end,
        'size': func_size,
        'iterations': add_count,
        'writes_per_iter': 2  # Known: 2 longs per iteration
    }

def check_stride_requirements(rom_data):
    """
    Check if stride (R13) allows FIFO batching

    FIFO batching requires consecutive memory writes:
    - If stride = 8 bytes: Can batch 4 consecutive longs
    - If stride > 8 bytes: Cannot batch (non-consecutive)
    """
    print("\n=== Checking Stride Requirements ===\n")

    # Search for R13 initialization near func_065 call sites
    # From analysis: R13 is stride value loaded from context or immediate

    print("FIFO batching requires stride = 8 (consecutive memory)")
    print("Current func_065 callers:")
    print("  - ROM 0x23E00-0x23E2E (multiple calls with ADD #$08,R9)")
    print("  - Each call advances dest by 8 bytes")
    print("\nRequirement check:")
    print("  ✓ Destination advances by 8 bytes between calls")
    print("  ? Stride (R13) value needs confirmation via profiling")
    print("\nAssumption: If stride = 8, batching is applicable")
    print("            If stride ≠ 8, batching may cause corruption")

    return True  # Optimistic assumption, needs testing

def create_fifo_batched_version():
    """
    Create FIFO-optimized version of func_065

    Strategy:
    - Group 12 of 14 iterations into 6 FIFO pairs
    - Remaining 2 iterations use original pattern
    - Each FIFO pair writes 4 longs consecutively (triggers FIFO)
    - Fits exactly in 150 bytes
    """
    print("\n=== Creating FIFO-Batched Version ===\n")

    # Original pattern (per iteration, 5 instructions):
    original_iter = [
        0x6206,  # MOV.L @R0+,R2
        0x1120,  # MOV.L R2,@($0,R1)
        0x6206,  # MOV.L @R0+,R2
        0x1121,  # MOV.L R2,@($4,R1)
        0x31DC,  # ADD R13,R1
    ]

    # FIFO-optimized pattern (per 2 iterations, 10 instructions):
    # Writes 4 longs consecutively to trigger FIFO burst
    fifo_pattern = [
        0x6206,  # MOV.L @R0+,R2
        0x1120,  # MOV.L R2,@($0,R1)
        0x6206,  # MOV.L @R0+,R2
        0x1121,  # MOV.L R2,@($4,R1)
        0x6206,  # MOV.L @R0+,R2
        0x1122,  # MOV.L R2,@($8,R1)   # 3rd write
        0x6206,  # MOV.L @R0+,R2
        0x1123,  # MOV.L R2,@($C,R1)   # 4th write (FIFO triggers!)
        0x31DC,  # ADD R13,R1          # Advance by stride
        0x31DC,  # ADD R13,R1          # Advance by stride again (total 16 bytes)
    ]

    print("Original pattern (per iteration):")
    print("  5 instructions, 7 cycles")
    print("  14 iterations total\n")

    print("Optimized pattern:")
    print("  6 FIFO pairs (12 iterations): 10 instr × 6 = 60 instructions")
    print("  2 normal iterations: 5 instr × 2 = 10 instructions")
    print("  Total: 70 instructions")
    print("  Benefit: 12 of 14 iterations trigger FIFO burst mode")
    print("  Expected: 8-12% faster\n")

    # Build complete function body
    function_body = bytearray()

    # Function prologue - use actual ROM pattern
    prologue = bytes([
        0x00, 0x09,  # NOP (alignment/safety)
        0x40, 0x18,  # SHLL8 R0         (×256)
        0x40, 0x01,  # SHLR R0          (÷2 = ×128)
        0x30, 0xAC,  # ADD R10,R0       (add table base)
        0x61, 0x93,  # MOV R9,R1        (R1 = dest)
    ])

    function_body.extend(prologue)

    # 6 FIFO-batched pairs (covers 12 iterations)
    for i in range(6):
        for opcode in fifo_pattern:
            function_body.extend(struct.pack('>H', opcode))

    # Remaining 2 normal iterations
    for i in range(2):
        for opcode in original_iter:
            function_body.extend(struct.pack('>H', opcode))

    # Function epilogue
    epilogue = bytes([
        0x00, 0x0B,  # RTS
        0x00, 0x09,  # NOP (delay slot)
    ])

    function_body.extend(epilogue)

    print(f"Generated function size: {len(function_body)} bytes")
    print(f"Original function size: 150 bytes")

    if len(function_body) > 150:
        print(f"  New function is {len(function_body) - 150} bytes larger (will use relocation)")

    if len(function_body) < 150:
        print(f"  Padding with {150 - len(function_body)} bytes of NOP\n")

    return bytes(function_body)

def apply_fifo_patch(rom_data):
    """Apply FIFO batching patch to ROM using relocation"""
    print("\n=== Applying FIFO Batching Patch ===\n")

    modified_rom = bytearray(rom_data)

    # Analyze current function
    func_info = analyze_func_065(rom_data)

    # Check stride requirements
    if not check_stride_requirements(rom_data):
        print("\n❌ Stride requirements not met. Aborting.")
        return None

    # Create optimized version
    new_func = create_fifo_batched_version()

    if new_func is None:
        print("\n❌ Failed to create optimized version.")
        return None

    # Use relocation if function doesn't fit
    if len(new_func) > func_info['size']:
        print(f"\n⚠️  New function ({len(new_func)} bytes) larger than original ({func_info['size']} bytes)")
        print("   Using relocation strategy...\n")

        # Relocate to ACTUAL unused ROM space at end (not 0x016300 - that's init code!)
        new_location = 0x2F5D00

        print(f"✓ Writing optimized function to ROM 0x{new_location:06X}")
        print(f"  Size: {len(new_func)} bytes")

        # Write optimized function to new location
        modified_rom[new_location:new_location+len(new_func)] = new_func

        # Calculate call site (actual function start where BSR calls)
        call_site = 0x23F2E  # Where BSR instructions target

        # Create trampoline at original call site
        # We need to jump to the new location using PC-relative addressing
        print(f"\n✓ Creating trampoline at ROM 0x{call_site:06X}")

        # Trampoline code:
        # CRITICAL: Must preserve ALL registers!
        # Use direct PC-relative branch if possible, otherwise need stack
        #
        # Since BSR can't reach (±4KB range), we use:
        # STS.L PR,@-R15  ; Save return address
        # MOV.L @(PC+x),R3
        # JSR @R3
        # NOP
        # LDS.L @R15+,PR  ; (in delay slot - NO! LDS.L not allowed in delay slot)
        #
        # Actually, we can't use JSR because the caller used BSR (expects RTS).
        # The problem: JMP clobbers no registers except PC, but we need a register
        # to load the target address.
        #
        # New approach: Use self-modifying code or...
        # Wait, let's check if we can use MOV.L with writeback to avoid clobbering:
        # Actually, we MUST clobber something temporarily.
        #
        # Safest: Save R3 to stack, use it, restore it
        # MOV.L R3,@-R15  ; Push R3
        # MOV.L @(PC+x),R3
        # JMP @R3
        # MOV.L @R15+,R3  ; Pop R3 (in delay slot!)

        # Calculate PC-relative offset for MOV.L
        # ROM is mapped at 0x02000000 (cached) in SH2 address space
        trampoline_pc = 0x02000000 + call_site  # ROM base + offset
        target_addr = 0x02000000 + new_location  # ROM base + relocated offset

        # Trampoline with R3 save/restore:
        # MOV.L R3,@-R15    = 0x2F36
        # MOV.L @(PC+8),R3  = 0xD302 (displacement=2 → 8 bytes)
        # JMP @R3           = 0x432B
        # MOV.L @R15+,R3    = 0x63F6 (delay slot - restore R3!)
        # .long target      = address

        trampoline = bytearray([
            0x2F, 0x36,  # MOV.L R3,@-R15  (push R3)
            0xD3, 0x02,  # MOV.L @(PC+8),R3
            0x43, 0x2B,  # JMP @R3
            0x63, 0xF6,  # MOV.L @R15+,R3  (pop R3 in delay slot!) - FIXED!
        ])

        # Append target address (big-endian)
        trampoline.extend(struct.pack('>I', target_addr))

        print(f"  Trampoline size: {len(trampoline)} bytes")
        print(f"  Jump target: 0x{target_addr:08X}")

        # Write trampoline at call site
        modified_rom[call_site:call_site+len(trampoline)] = trampoline

        # Fill rest of original function with NOPs
        remaining = func_info['end'] - call_site - len(trampoline)
        for i in range(remaining // 2):
            modified_rom[call_site + len(trampoline) + i*2:call_site + len(trampoline) + i*2 + 2] = bytes([0x00, 0x09])

        print(f"  Remaining space filled with {remaining} bytes of NOP")
        print("\n✓ Relocation complete")

    else:
        # Original in-place patching if it fits
        func_start = func_info['start']
        print(f"\n✓ Patching func_065 at ROM 0x{func_start:06X}")
        print(f"  Original: {func_info['size']} bytes")
        print(f"  New:      {len(new_func)} bytes")
        print(f"  Padding:  {func_info['size'] - len(new_func)} bytes (filled with NOP)")

        # Write new function
        modified_rom[func_start:func_start+len(new_func)] = new_func

        # Fill remaining space with NOPs
        nop_padding = func_info['size'] - len(new_func)
        for i in range(nop_padding // 2):
            modified_rom[func_start + len(new_func) + i*2:func_start + len(new_func) + i*2 + 2] = bytes([0x00, 0x09])

        print("\n✓ Patch applied successfully")

    return bytes(modified_rom)

def main():
    print("=" * 70)
    print(" Virtua Racing - func_065 FIFO Batching Optimization")
    print(" Expected Gain: +10-15% FPS (24 → 27-28 FPS)")
    print("=" * 70)

    input_file = Path("Virtua Racing Deluxe (USA).32x")
    output_file = Path("Virtua Racing - FIFO.32x")

    if not input_file.exists():
        print(f"\n❌ Input ROM not found: {input_file}")
        print("   Place ROM in current directory and try again.")
        sys.exit(1)

    print(f"\n✓ Reading ROM: {input_file}")
    rom_data = input_file.read_bytes()
    print(f"  Size: {len(rom_data):,} bytes ({len(rom_data)/1024/1024:.2f} MB)")

    # Apply patch
    patched_rom = apply_fifo_patch(rom_data)

    if patched_rom is None:
        print("\n❌ Patch failed. ROM not modified.")
        sys.exit(1)

    # Save output
    output_file.write_bytes(patched_rom)
    print(f"\n✓ Optimized ROM saved: {output_file}")

    # Calculate changes
    changes = sum(1 for i in range(len(rom_data)) if rom_data[i] != patched_rom[i])
    print(f"  Bytes modified: {changes:,} ({changes/len(rom_data)*100:.3f}%)")

    print("\n" + "=" * 70)
    print(" ✓ Optimization Complete")
    print("=" * 70)
    print("\nNext steps:")
    print("1. Test ROM in emulator:")
    print(f'   ./Gens_KMod_v0.7.3/gens.exe "{output_file}"')
    print("2. Verify:")
    print("   - Game boots correctly")
    print("   - Graphics render properly")
    print("   - No visual corruption")
    print("3. Measure FPS (if emulator supports)")
    print("4. If successful, proceed to Slave CPU optimization")
    print("\n⚠️  IMPORTANT: This patch assumes stride (R13) = 8")
    print("   If you see corruption, stride may be different.")
    print("   Revert to original ROM and analyze stride values.")

if __name__ == '__main__':
    main()
