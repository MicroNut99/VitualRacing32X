#!/usr/bin/env python3
"""
ROM to DC.W Converter - Generates 100% accurate assembly from ROM bytes.

This tool outputs pure DC.W statements that will reassemble to the exact
original bytes. No instruction decoding errors possible.

Usage:
    python rom_to_dcw.py <rom_file> <start_offset> <end_offset> [output_file]

Example:
    python rom_to_dcw.py "Virtua Racing Deluxe (USA).32x" 0x200 0x2200 code_200.asm
"""

import sys
import struct

def rom_to_dcw(rom_path, start_offset, end_offset, output_path=None, org_address=None):
    """Convert ROM bytes to DC.W assembly statements."""

    with open(rom_path, 'rb') as f:
        f.seek(start_offset)
        data = f.read(end_offset - start_offset)

    # Default org is same as file offset (for 68K code in 32X ROM)
    if org_address is None:
        org_address = start_offset

    lines = []
    lines.append(f"; ============================================================================")
    lines.append(f"; Code Section (${org_address:06X}-${org_address + len(data) - 1:06X})")
    lines.append(f"; Generated from ROM bytes - guaranteed accurate")
    lines.append(f"; ============================================================================")
    lines.append(f"")
    lines.append(f"        org     ${org_address:06X}")
    lines.append(f"")

    # Process 16-bit words
    offset = 0
    while offset < len(data):
        addr = org_address + offset

        if offset + 1 < len(data):
            # Full word
            word = struct.unpack('>H', data[offset:offset+2])[0]
            lines.append(f"        dc.w    ${word:04X}        ; ${addr:06X}")
            offset += 2
        else:
            # Odd byte at end
            byte = data[offset]
            lines.append(f"        dc.b    ${byte:02X}          ; ${addr:06X}")
            offset += 1

    output = '\n'.join(lines) + '\n'

    if output_path:
        with open(output_path, 'w') as f:
            f.write(output)
        print(f"Written {len(data)} bytes as DC.W to {output_path}")
    else:
        print(output)

    return len(data)

def regenerate_all_sections(rom_path, output_dir):
    """Regenerate all section files from ROM."""
    import os

    # Section definitions: (start_offset, end_offset, filename)
    # Based on 8KB sections
    sections = []

    # Header
    sections.append((0x000000, 0x000200, "header.asm"))

    # 68K code sections (8KB each from $200 onwards)
    addr = 0x200
    while addr < 0x300000:  # 3MB ROM
        end = min(addr + 0x2000, 0x300000)
        filename = f"code_{addr:x}.asm"
        sections.append((addr, end, filename))
        addr = end

    os.makedirs(output_dir, exist_ok=True)

    total_bytes = 0
    for start, end, filename in sections:
        path = os.path.join(output_dir, filename)
        total_bytes += rom_to_dcw(rom_path, start, end, path)

    print(f"\nTotal: {total_bytes} bytes in {len(sections)} section files")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    if sys.argv[1] == '--all':
        if len(sys.argv) < 4:
            print("Usage: python rom_to_dcw.py --all <rom_file> <output_dir>")
            sys.exit(1)
        regenerate_all_sections(sys.argv[2], sys.argv[3])
    else:
        rom_path = sys.argv[1]
        start = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0
        end = int(sys.argv[3], 0) if len(sys.argv) > 3 else start + 0x2000
        output = sys.argv[4] if len(sys.argv) > 4 else None
        rom_to_dcw(rom_path, start, end, output)
