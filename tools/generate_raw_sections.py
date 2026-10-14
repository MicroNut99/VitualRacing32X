#!/usr/bin/env python3
"""
Generate raw DC.W sections from ROM that are guaranteed to assemble correctly.
This creates a baseline that can be annotated with proper instructions later.
"""

import struct
import os
import sys

ROM_FILE = "Virtua Racing Deluxe (USA).32x"

# Section boundaries (from existing structure)
# Format: (start_offset, end_offset, name)
SECTIONS = [
    (0x000000, 0x000200, "header"),      # Vector table + ROM header
    (0x000200, 0x002200, "code_200"),    # Code section
    (0x002200, 0x004200, "code_2200"),
    (0x004200, 0x006200, "code_4200"),
    (0x006200, 0x008200, "code_6200"),
    (0x008200, 0x00A200, "code_8200"),
    (0x00A200, 0x00C200, "code_a200"),
    (0x00C200, 0x00E200, "code_c200"),
    (0x00E200, 0x010200, "code_e200"),
    (0x010200, 0x012200, "code_10200"),
    (0x012200, 0x014200, "code_12200"),
    (0x014200, 0x016200, "code_14200"),
    (0x016200, 0x018200, "code_16200"),
    # Continue for all sections up to ROM end
]

def generate_section(rom_data, start, end, name, output_dir):
    """Generate a raw DC.W section file"""
    filepath = os.path.join(output_dir, f"{name}.asm")

    with open(filepath, 'w') as f:
        f.write(f"; ============================================================================\n")
        f.write(f"; Section: {name} (${start:06X}-${end-1:06X})\n")
        f.write(f"; Raw data representation for reassembly\n")
        f.write(f"; ============================================================================\n\n")
        f.write(f"        org     ${start:06X}\n\n")
        f.write(f"{name}:\n")

        pos = start
        while pos < end:
            # Output 8 words per line (16 bytes)
            words_per_line = 8
            words = []
            line_start = pos

            for i in range(words_per_line):
                if pos + 2 <= end:
                    word = struct.unpack('>H', rom_data[pos:pos+2])[0]
                    words.append(f"${word:04X}")
                    pos += 2
                else:
                    break

            if words:
                f.write(f"        DC.W    {','.join(words)}  ; ${line_start:06X}\n")

    return filepath

def get_all_section_boundaries(rom_size):
    """Generate section boundaries for the entire ROM"""
    sections = []

    # First section is always the header
    sections.append((0x000000, 0x000200, "header"))

    # Then 8KB sections for the rest
    pos = 0x000200
    section_size = 0x2000  # 8KB

    while pos < rom_size:
        end = min(pos + section_size, rom_size)
        name = f"code_{pos:05x}"
        sections.append((pos, end, name))
        pos = end

    return sections

def main():
    if not os.path.exists(ROM_FILE):
        print(f"Error: ROM file not found: {ROM_FILE}")
        return 1

    with open(ROM_FILE, 'rb') as f:
        rom_data = f.read()

    print(f"Loaded ROM: {len(rom_data)} bytes ({len(rom_data)/1024/1024:.1f} MB)")

    # Create output directory
    output_dir = "disasm/sections_raw"
    os.makedirs(output_dir, exist_ok=True)

    # Generate section boundaries
    sections = get_all_section_boundaries(len(rom_data))
    print(f"Generating {len(sections)} sections...")

    # Generate each section
    for start, end, name in sections:
        filepath = generate_section(rom_data, start, end, name, output_dir)
        size = end - start
        print(f"  {name}: ${start:06X}-${end-1:06X} ({size} bytes)")

    # Generate master include file
    master_file = os.path.join("disasm", "vrd_raw.asm")
    with open(master_file, 'w') as f:
        f.write("; ============================================================================\n")
        f.write("; Virtua Racing Deluxe - Raw Data Assembly\n")
        f.write("; Generated from ROM for guaranteed correct reassembly\n")
        f.write("; ============================================================================\n\n")

        f.write("        include \"sections/mars_defs.asm\"\n\n")

        for start, end, name in sections:
            f.write(f"        include \"sections_raw/{name}.asm\"\n")

    print(f"\nGenerated master file: {master_file}")
    print(f"Output directory: {output_dir}")

    return 0

if __name__ == "__main__":
    sys.exit(main())
