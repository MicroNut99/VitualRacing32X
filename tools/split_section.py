#!/usr/bin/env python3
"""
Split raw DC.W sections at specified address boundaries.
Creates multiple annotated module files from a single raw section.

Handles arbitrary byte-aligned splits (not just 16-byte aligned).

Usage:
    python3 split_section.py <input_section> <output_dir> <split_points>

Example:
    python3 split_section.py sections_raw/code_00200.asm modules/68k/ \
        "0x200:boot/init_sequence" \
        "0x1684:main-loop/vint_handler" \
        "0x17EE:input/controller_read"
"""

import sys
import os
import re
from pathlib import Path

def parse_raw_section(filepath):
    """Parse a raw section file and extract byte-level data."""
    bytes_data = {}

    with open(filepath, 'r') as f:
        for line in f:
            # Match: DC.W    $XXXX,$XXXX,...  ; $XXXXXX
            match = re.match(r'\s*DC\.W\s+(.+?)\s+;\s*\$([0-9A-Fa-f]+)', line)
            if match:
                words_str = match.group(1)
                addr = int(match.group(2), 16)

                # Parse the word values and store as individual bytes
                for w in words_str.split(','):
                    w = w.strip()
                    if w.startswith('$'):
                        val = int(w[1:], 16)
                        # Store high byte, then low byte
                        bytes_data[addr] = (val >> 8) & 0xFF
                        bytes_data[addr + 1] = val & 0xFF
                        addr += 2

    return bytes_data

def generate_module(output_path, start_addr, end_addr, bytes_data, module_name):
    """Generate an annotated module file for an address range."""

    # Ensure directory exists
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    # Calculate size
    size = end_addr - start_addr

    with open(output_path, 'w') as f:
        f.write("; ============================================================================\n")
        f.write(f"; Virtua Racing Deluxe - {module_name}\n")
        f.write(f"; Module: {output_path.split('modules/')[-1] if 'modules/' in output_path else output_path}\n")
        f.write(f"; Address: ${start_addr:06X}-${end_addr-1:06X} ({size} bytes)\n")
        f.write("; ============================================================================\n")
        f.write(";\n")
        f.write("; TODO: Add function annotations and documentation\n")
        f.write(";\n")
        f.write("; ============================================================================\n\n")
        f.write(f"        org     ${start_addr:06X}\n\n")

        # Find label name from module path
        label = os.path.basename(output_path).replace('.asm', '').replace('-', '_')
        f.write(f"{label}:\n")

        # Write data for this address range, 8 words per line
        addr = start_addr
        while addr < end_addr:
            words = []
            line_addr = addr

            # Collect up to 8 words (16 bytes) for this line
            for _ in range(8):
                if addr + 1 < end_addr and addr in bytes_data and (addr + 1) in bytes_data:
                    high = bytes_data[addr]
                    low = bytes_data[addr + 1]
                    words.append((high << 8) | low)
                    addr += 2
                elif addr < end_addr:
                    # Handle odd byte at end (should be rare)
                    if addr in bytes_data:
                        words.append(bytes_data[addr] << 8)
                    addr += 1
                    break
                else:
                    break

            if words:
                words_str = ','.join(f'${w:04X}' for w in words)
                f.write(f"        DC.W    {words_str}  ; ${line_addr:06X}\n")

        f.write("\n; ============================================================================\n")
        f.write(f"; End of {module_name}\n")
        f.write("; ============================================================================\n")

    print(f"  Created: {output_path} (${start_addr:06X}-${end_addr-1:06X}, {size} bytes)")

def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    input_file = sys.argv[1]
    output_dir = sys.argv[2]
    split_specs = sys.argv[3:]

    # Parse split specifications: "0xADDR:path/to/module"
    splits = []
    for spec in split_specs:
        addr_str, path = spec.split(':')
        addr = int(addr_str, 16)
        splits.append((addr, path))

    # Sort by address
    splits.sort(key=lambda x: x[0])

    # Parse the input section at byte level
    print(f"Reading: {input_file}")
    bytes_data = parse_raw_section(input_file)

    if not bytes_data:
        print("ERROR: No data found in input file")
        sys.exit(1)

    # Find section bounds
    all_addrs = sorted(bytes_data.keys())
    section_start = all_addrs[0]
    section_end = all_addrs[-1] + 1

    print(f"Section range: ${section_start:06X}-${section_end:06X} ({len(bytes_data)} bytes)")
    print(f"Split points: {len(splits)}")

    # Validate split points are within section bounds
    for addr, path in splits:
        if addr < section_start or addr >= section_end:
            print(f"WARNING: Split point ${addr:06X} is outside section range")

    # Generate modules for each range
    print("\nGenerating modules:")

    for i, (start_addr, module_path) in enumerate(splits):
        # Determine end address (next split point or section end)
        if i + 1 < len(splits):
            end_addr = splits[i + 1][0]
        else:
            end_addr = section_end

        # Full output path
        output_path = os.path.join(output_dir, module_path + ".asm")
        module_name = module_path.replace('/', ' - ').replace('-', ' ').title()

        generate_module(output_path, start_addr, end_addr, bytes_data, module_name)

    print("\nDone! Update vrd_modular.asm to include the new modules.")

if __name__ == '__main__':
    main()
