#!/usr/bin/env python3
"""
Find SH2 entry points in Virtua Racing ROM.

According to 32X architecture, the SH2 Boot ROM reads entry points from
specific locations in the cartridge ROM.
"""

import sys
import struct

def read_long_be(data, offset):
    """Read big-endian 32-bit value."""
    return struct.unpack('>I', data[offset:offset+4])[0]

def is_sh2_address(addr):
    """Check if address looks like a valid SH2 address."""
    # SH2 addresses:
    # 0x00000000-0x00004000: Boot ROM / internal
    # 0x02000000-0x023FFFFF: SDRAM (256KB)
    # 0x06000000-0x062FFFFF: ROM (uncached)
    # 0x20000000-0x202FFFFF: ROM (cached)
    # 0x22000000-0x223FFFFF: SDRAM (cached)
    if 0x06000000 <= addr < 0x06300000:  # ROM uncached
        return True
    if 0x20000000 <= addr < 0x20300000:  # ROM cached
        return True
    if 0x02000000 <= addr < 0x02040000:  # SDRAM uncached
        return True
    if 0x22000000 <= addr < 0x22040000:  # SDRAM cached
        return True
    if 0x00000000 <= addr < 0x00004000:  # Internal
        return True
    return False

def main():
    if len(sys.argv) < 2:
        print("Usage: find_sh2_entry.py <rom_file>")
        print("\nSearches for SH2 entry points in 32X ROM header")
        sys.exit(1)

    try:
        with open(sys.argv[1], 'rb') as f:
            rom = f.read()
    except FileNotFoundError:
        print(f"Error: ROM file '{sys.argv[1]}' not found")
        sys.exit(1)

    print("=" * 70)
    print("SH2 Entry Point Search - Virtua Racing Deluxe")
    print("=" * 70)

    # Check MARS security area (0x3C0-0x3EF)
    print("\n[1] MARS Security Area (0x3C0-0x3EF):")
    print("-" * 70)

    # MARS signature
    mars = rom[0x3C0:0x3D0].decode('ascii', errors='replace')
    print(f"0x3C0: {mars!r}")

    # Security parameters (0x3D0-0x3DF)
    print(f"\n0x3D0: {rom[0x3D0:0x3E0].hex(' ')}")
    for i in range(0x3D0, 0x3E0, 4):
        val = read_long_be(rom, i)
        print(f"  0x{i:03X}: 0x{val:08X}")

    # SH2 address table (0x3E0-0x3EF)
    print(f"\n[2] SH2 Address Table (0x3E0-0x3EF):")
    print("-" * 70)

    for i in range(0x3E0, 0x3F0, 4):
        addr = read_long_be(rom, i)
        is_valid = is_sh2_address(addr)
        status = "✓ SH2" if is_valid else "✗"

        # Convert SH2 address to ROM offset
        rom_offset = None
        if 0x06000000 <= addr < 0x06300000:
            rom_offset = addr - 0x06000000
        elif 0x20000000 <= addr < 0x20300000:
            rom_offset = addr - 0x20000000

        if rom_offset is not None:
            print(f"  0x{i:03X}: 0x{addr:08X}  {status}  → ROM offset 0x{rom_offset:X}")
        else:
            print(f"  0x{i:03X}: 0x{addr:08X}  {status}")

    # Look for "Hot Start" entry points - typically at 0x3E4 and 0x3E8
    print(f"\n[3] Potential SH2 Entry Points:")
    print("-" * 70)

    master_entry = read_long_be(rom, 0x3E4)
    slave_entry = read_long_be(rom, 0x3E8)

    print(f"  Master (0x3E4): 0x{master_entry:08X}")
    if is_sh2_address(master_entry):
        if 0x06000000 <= master_entry < 0x06300000:
            rom_off = master_entry - 0x06000000
            print(f"    → ROM offset 0x{rom_off:X}")
        elif 0x20000000 <= master_entry < 0x20300000:
            rom_off = master_entry - 0x20000000
            print(f"    → ROM offset 0x{rom_off:X} (cached)")

    print(f"\n  Slave  (0x3E8): 0x{slave_entry:08X}")
    if is_sh2_address(slave_entry):
        if 0x06000000 <= slave_entry < 0x06300000:
            rom_off = slave_entry - 0x06000000
            print(f"    → ROM offset 0x{rom_off:X}")
        elif 0x20000000 <= slave_entry < 0x20300000:
            rom_off = slave_entry - 0x20000000
            print(f"    → ROM offset 0x{rom_off:X} (cached)")

    # Scan entire security region for SH2 addresses
    print(f"\n[4] All SH2 Addresses in Security Region (0x3C0-0x3FF):")
    print("-" * 70)

    for offset in range(0x3C0, 0x400, 4):
        val = read_long_be(rom, offset)
        if is_sh2_address(val):
            rom_off = None
            if 0x06000000 <= val < 0x06300000:
                rom_off = val - 0x06000000
            elif 0x20000000 <= val < 0x20300000:
                rom_off = val - 0x20000000
            elif 0x02000000 <= val < 0x02040000:
                rom_off = f"SDRAM+{val - 0x02000000:X}"
            elif 0x22000000 <= val < 0x22040000:
                rom_off = f"SDRAM+{val - 0x22000000:X}"

            if rom_off is not None:
                if isinstance(rom_off, int):
                    print(f"  0x{offset:03X}: 0x{val:08X} → ROM 0x{rom_off:X}")
                else:
                    print(f"  0x{offset:03X}: 0x{val:08X} → {rom_off}")

    print("\n" + "=" * 70)

if __name__ == '__main__':
    main()
