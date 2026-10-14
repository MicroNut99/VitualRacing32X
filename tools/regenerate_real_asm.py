#!/usr/bin/env python3
"""
Regenerate all sections from ROM with real assembly mnemonics.

This creates the real-asm branch content by disassembling the ROM
directly into real 68K assembly (not DC.W format).

Usage: python regenerate_real_asm.py
"""

import sys
import os
from pathlib import Path

# Add tools to path
sys.path.insert(0, str(Path(__file__).parent))

from disasm_to_asm import AssemblyGenerator

# Configuration
ROM_PATH = Path(__file__).parent.parent / "Virtua Racing Deluxe (USA).32x"
SECTIONS_DIR = Path(__file__).parent.parent / "disasm" / "sections"

# Section definitions: (start, end, filename)
# Header is special (keep as DC.W data)
# All code sections are 8KB
SECTIONS = []

# Header (keep as data - no conversion)
# SECTIONS.append((0x000000, 0x000200, "header.asm", True))  # is_data=True

# Generate 8KB code sections from $200 to $300000
addr = 0x200
while addr < 0x300000:
    end = min(addr + 0x2000, 0x300000)
    filename = f"code_{addr:x}.asm"
    SECTIONS.append((addr, end, filename, False))
    addr = end


def regenerate_section(rom_data, start, end, filename, is_data=False):
    """Regenerate a single section."""
    output_path = SECTIONS_DIR / filename

    if is_data:
        # Keep data sections as DC.W (use rom_to_dcw format)
        from rom_to_dcw import rom_to_dcw
        rom_to_dcw(str(ROM_PATH), start, end, str(output_path))
        return "data"

    # Generate real assembly
    gen = AssemblyGenerator(rom_data, start, end)
    output = gen.generate(use_dcw=False)  # Real mnemonics!

    with open(output_path, 'w') as f:
        f.write(output)

    return "asm"


def main():
    if not ROM_PATH.exists():
        print(f"ERROR: ROM not found at {ROM_PATH}")
        sys.exit(1)

    print(f"=== Regenerate Real Assembly ===")
    print(f"ROM: {ROM_PATH}")
    print(f"Output: {SECTIONS_DIR}")
    print(f"Sections: {len(SECTIONS)}")
    print()

    with open(ROM_PATH, 'rb') as f:
        rom_data = f.read()

    stats = {'asm': 0, 'data': 0, 'error': 0}

    for start, end, filename, is_data in SECTIONS:
        try:
            result = regenerate_section(rom_data, start, end, filename, is_data)
            stats[result] += 1
            size_kb = (end - start) / 1024
            print(f"OK: {filename} (${start:06X}-${end:06X}, {size_kb:.1f}KB, {result})")
        except Exception as e:
            stats['error'] += 1
            print(f"ERROR: {filename}: {e}")

    print()
    print(f"=== Summary ===")
    print(f"Assembly sections: {stats['asm']}")
    print(f"Data sections: {stats['data']}")
    print(f"Errors: {stats['error']}")


if __name__ == "__main__":
    main()
