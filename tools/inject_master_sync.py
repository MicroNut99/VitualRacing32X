#!/usr/bin/env python3
"""
Master SH2 Integration - Sync Buffer Initialization and Slave Dispatch

Injects synchronization code into Master rendering engine:
1. Initializes sync buffer in func_001 (display list processor)
2. Adds Slave dispatch in final_exit (frame completion)

This enables Master-Slave handshake for parallel polygon rendering.
"""

import struct
from pathlib import Path


def find_func_001_entry(rom_data: bytearray) -> int:
    """Find func_001 entry point (display list processor).

    func_001 at CPU 0x0222301C = ROM 0x023024 (after header adjustment)
    Pattern: STS.L PR,@-R15 (0x4F 0x22)
    """
    pattern = bytes([0x4F, 0x22])

    # Search in ROM range where func_001 is expected
    # Based on annotation, func_001 starts around 0x023024
    search_start = 0x023000
    search_end = 0x023100

    for i in range(search_start, search_end):
        if i + 2 < len(rom_data) and rom_data[i:i+2] == pattern:
            print(f"Found STS.L PR pattern at ROM 0x{i:06X} (candidate for func_001)")
            return i

    return -1


def find_final_exit(rom_data: bytearray) -> int:
    """Find final_exit point (frame completion).

    final_exit at CPU 0x0222399A = ROM 0x02399A
    Pattern: RTS (0x00 0x0B)
    But need to find the right one - should be near end of rendering engine
    """
    pattern = bytes([0x00, 0x0B])

    # Search in rendering engine region
    search_start = 0x023900
    search_end = 0x023A00

    candidates = []
    for i in range(search_start, search_end):
        if i + 2 < len(rom_data) and rom_data[i:i+2] == pattern:
            candidates.append(i)

    print(f"Found {len(candidates)} RTS candidates in final_exit region:")
    for cand in candidates[-3:]:  # Show last 3
        print(f"  ROM 0x{cand:06X}")

    if candidates:
        return candidates[-1]  # Return last RTS (should be final_exit)

    return -1


def create_sync_init_code() -> bytes:
    """Create sync buffer initialization code.

    Clears all sync buffer flags and initializes context pointers.
    Code size: ~60 bytes (SH2)

    Assembly (pseudocode):
        mov.l   sync_base, r1          ; R1 = 0x22000400
        mov     #0, r0
        mov.l   r0, @(0x00, r1)        ; Clear MASTER_READY
        mov.l   r0, @(0x04, r1)        ; Clear SLAVE_READY
        mov.l   r0, @(0x08, r1)        ; Clear MASTER_DONE
        mov.l   r0, @(0x0C, r1)        ; Clear SLAVE_DONE

        mov.l   context_addr, r0       ; R0 = 0xC0000700
        mov.l   r0, @(0x20, r1)        ; Store CONTEXT_PTR

        mov.l   display_list, r0       ; R0 = current display list
        mov.l   r0, @(0x24, r1)        ; Store DISPLAY_LIST_PTR

        mov.l   frame_buffer, r0       ; R0 = 0x24000000
        mov.l   r0, @(0x28, r1)        ; Store FRAME_BUFFER_PTR
        rts
    """

    code = bytearray()

    # mov.l sync_base, r1  (D1 xx yy zz where PC-relative)
    code.extend([0xD1, 0x0A])  # mov.l @(40,PC), r1

    # mov #0, r0
    code.extend([0xE0, 0x00])

    # Clear flags (4× mov.l r0, @(offset,r1))
    # mov.l r0, @(0x00,r1)
    code.extend([0x20, 0x10])

    # mov.l r0, @(0x04,r1)
    code.extend([0x21, 0x10])

    # mov.l r0, @(0x08,r1)
    code.extend([0x22, 0x10])

    # mov.l r0, @(0x0C,r1)
    code.extend([0x23, 0x10])

    # Set context pointer
    # mov.l context_addr, r0
    code.extend([0xD0, 0x08])  # mov.l @(32,PC), r0

    # mov.l r0, @(0x20,r1)
    code.extend([0x24, 0x10])

    # Note: Display list pointer (R13) is already set
    # Frame buffer is constant (0x24000000)

    # Return
    code.extend([0x00, 0x0B])  # RTS
    code.extend([0x00, 0x09])  # NOP (delay slot)

    # Align to 4-byte boundary for literals
    while len(code) % 4 != 0:
        code.extend([0x00, 0x09])

    # Literals
    # sync_base = 0x22000400
    code.extend(struct.pack('>I', 0x22000400))

    # context_addr = 0xC0000700
    code.extend(struct.pack('>I', 0xC0000700))

    return bytes(code)


def create_slave_dispatch_code() -> bytes:
    """Create Slave dispatch and sync code.

    Called at frame completion (final_exit).
    Dispatches work to Slave, waits for completion.

    Code size: ~80 bytes
    """

    code = bytearray()

    # Load sync buffer
    # mov.l sync_base, r14
    code.extend([0xD1, 0x14])  # mov.l @(80,PC), r14

    # Wait for Slave ready (with timeout)
    # mov #60, r2 (timeout iterations)
    code.extend([0xE2, 0x3C])

    # Loop: check SLAVE_READY
    # mov.l @(0x04, r14), r0
    code.extend([0x61, 0x14])  # mov.l @(4,r14), r0

    # mov.l ready_magic, r1
    code.extend([0xD1, 0x10])  # mov.l @(64,PC), r1

    # cmp/eq r1, r0
    code.extend([0x30, 0x14])

    # bt ready (skip forward)
    code.extend([0x89, 0x04])  # bt +8 instructions

    # dt r2 (decrement timeout)
    code.extend([0x72, 0x10])

    # bf loop (loop if not zero)
    code.extend([0x8B, 0xF8])  # bf -8 instructions

    # Timeout fallback: skip Slave
    # bra skip_slave
    code.extend([0xAF, 0x1C])  # bra +56 instructions (to after dispatch)
    code.extend([0x00, 0x09])

    # ready: Set work parameters
    # mov.l #800, r0 (polygon count)
    code.extend([0xD0, 0x0C])  # mov.l @(48,PC), r0

    # mov.l r0, @(0x10, r14) (POLYGON_COUNT)
    code.extend([0x24, 0x10])  # mov.l r0, @(16,r14)

    # Set Slave start/end (for now: 400-799)
    # mov.l #400, r0
    code.extend([0xD0, 0x0A])

    # mov.l r0, @(0x14, r14)
    code.extend([0x25, 0x10])

    # mov.l #799, r0
    code.extend([0xD0, 0x09])

    # mov.l r0, @(0x18, r14)
    code.extend([0x26, 0x10])

    # Signal Slave: MASTER_READY = "WORK"
    # mov.l work_magic, r0
    code.extend([0xD0, 0x08])  # mov.l @(32,PC), r0

    # mov.l r0, @(0x00, r14)
    code.extend([0x20, 0x10])

    # Signal Master done
    # mov.l done_magic, r0
    code.extend([0xD0, 0x07])  # mov.l @(28,PC), r0

    # mov.l r0, @(0x08, r14)
    code.extend([0x22, 0x10])

    # Wait for Slave completion (with timeout)
    # mov #1000, r2 (longer timeout)
    code.extend([0xD2, 0x14])  # mov.l @(80,PC), r2

    # Loop: check SLAVE_DONE
    # mov.l @(0x0C, r14), r0
    code.extend([0x63, 0x14])  # mov.l @(12,r14), r0

    # cmp/eq done_magic, r0
    code.extend([0xD1, 0x04])  # mov.l done_magic, r1
    code.extend([0x30, 0x14])

    # bt both_done
    code.extend([0x89, 0x02])

    # dt r2, bf loop
    code.extend([0x72, 0x10])
    code.extend([0x8B, 0xF8])

    # skip_slave/both_done: Return
    code.extend([0x00, 0x0B])  # RTS
    code.extend([0x00, 0x09])  # NOP

    # Align to 4-byte boundary
    while len(code) % 4 != 0:
        code.extend([0x00, 0x09])

    # Literals (big-endian 32-bit values)
    code.extend(struct.pack('>I', 0x22000400))  # sync_base
    code.extend(struct.pack('>I', 0x800))       # 800 (polygon count)
    code.extend(struct.pack('>I', 0x400))       # 400 (slave start)
    code.extend(struct.pack('>I', 0x31F))       # 799 (slave end)
    code.extend(struct.pack('>I', 0x574F524B))  # "WORK"
    code.extend(struct.pack('>I', 0x444F4E45))  # "DONE"
    code.extend(struct.pack('>I', 0x52454459))  # "REDY"
    code.extend(struct.pack('>I', 0x3E8))       # 1000 (timeout)

    return bytes(code)


def inject_master_sync(input_rom: str, output_rom: str) -> bool:
    """Inject Master synchronization code into ROM."""

    print("=" * 70)
    print("MASTER SH2 INTEGRATION - SYNC BUFFER AND SLAVE DISPATCH")
    print("=" * 70)
    print()

    # Load ROM
    rom_path = Path(input_rom)
    if not rom_path.exists():
        print(f"ERROR: ROM not found: {input_rom}")
        return False

    rom_data = bytearray(rom_path.read_bytes())
    print(f"ROM loaded: {len(rom_data):,} bytes")
    print()

    # Find func_001 entry
    func_001_offset = find_func_001_entry(rom_data)
    if func_001_offset < 0:
        print("ERROR: Could not find func_001 entry point")
        print("Manual integration required - see PHASE_1_INTEGRATION_GUIDE.md")
        return False

    print(f"✓ Found func_001 at ROM 0x{func_001_offset:06X}")

    # Find final_exit
    final_exit_offset = find_final_exit(rom_data)
    if final_exit_offset < 0:
        print("ERROR: Could not find final_exit")
        return False

    print(f"✓ Found final_exit at ROM 0x{final_exit_offset:06X}")
    print()

    print("=" * 70)
    print("INTEGRATION STATUS")
    print("=" * 70)
    print()
    print("Phase 2 integration requires MANUAL CODE INSERTION at:")
    print()
    print(f"1. func_001 (ROM 0x{func_001_offset:06X}):")
    print("   - After STS.L PR,@-R15")
    print("   - Before BSR func_007")
    print("   - Insert: sync buffer initialization code (~30 bytes)")
    print()
    print(f"2. final_exit (ROM 0x{final_exit_offset:06X}):")
    print("   - Before RTS instruction")
    print("   - Insert: Slave dispatch code (~80 bytes)")
    print()
    print("See PHASE_2_MASTER_INTEGRATION.md for detailed code snippets")
    print()

    return True


def main():
    import sys

    if len(sys.argv) < 2:
        print("Usage: python3 inject_master_sync.py <input.32x> [output.32x]")
        print()
        print("This tool assists with Phase 2 Master integration.")
        print("Current implementation: Analysis and guidance only")
        print("Manual code injection required.")
        sys.exit(1)

    input_rom = sys.argv[1]
    output_rom = sys.argv[2] if len(sys.argv) > 2 else "vrd_master_integrated.32x"

    success = inject_master_sync(input_rom, output_rom)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
