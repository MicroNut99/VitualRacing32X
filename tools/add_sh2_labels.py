#!/usr/bin/env python3
"""
Add function labels to annotated SH2 module files.

Takes an annotated module and adds labels at function boundaries.

Usage:
    python3 add_sh2_labels.py <module_file> <rom_file> [--output <output_file>]
"""

import re
import sys
import argparse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from identify_sh2_functions import SH2FunctionAnalyzer


def add_labels_to_module(module_path, rom_path, output_path=None):
    """Add function labels to a module file."""

    # Read the module file
    with open(module_path, 'r') as f:
        lines = f.readlines()

    # Parse org directive to get start address
    org_line = None
    for line in lines:
        match = re.match(r'\s*org\s+\$([0-9A-Fa-f]+)', line)
        if match:
            org_line = int(match.group(1), 16)
            break

    if org_line is None:
        print("Error: Could not find org directive")
        return

    # Determine end address (rough estimate from file)
    # We'll look for the last DC.W line
    last_dcw_addr = org_line
    for line in lines:
        match = re.match(r'\s+DC\.W\s+.*;\s*\$([0-9A-Fa-f]+)', line)
        if match:
            addr = int(match.group(1), 16)
            if addr > last_dcw_addr:
                last_dcw_addr = addr

    end_addr = last_dcw_addr + 0x10  # Add padding

    print(f"Module range: ${org_line:06X} - ${end_addr:06X}")

    # Analyze functions in ROM
    with open(rom_path, 'rb') as f:
        rom_data = f.read()

    analyzer = SH2FunctionAnalyzer(rom_data, org_line, end_addr)
    functions = analyzer.analyze()

    print(f"Found {len(functions)} functions")

    # Create address-to-function mapping
    func_map = {}
    for i, func in enumerate(functions):
        offset = func['start_offset']
        func_map[offset] = {
            'num': i + 1,
            'size': func['size'],
            'addr': func['start_addr'],
        }

    # Process module file and insert labels
    output_lines = []
    for line in lines:
        # Check if this line starts a new function
        match = re.match(r'\s+DC\.W\s+.*;\s*\$([0-9A-Fa-f]+)', line)
        if match:
            addr = int(match.group(1), 16)
            if addr in func_map:
                func_info = func_map[addr]
                # Add function label and comment
                output_lines.append(f"\n; ----------------------------------------------------------------------\n")
                output_lines.append(f"; SH2 Function #{func_info['num']:02d}\n")
                output_lines.append(f"; Address: ${func_info['addr']:08X}\n")
                output_lines.append(f"; Size: {func_info['size']} bytes\n")
                output_lines.append(f"; ----------------------------------------------------------------------\n")
                output_lines.append(f"sh2_func_{func_info['num']:02d}:                     ; @ ${func_info['addr']:08X}\n")

        output_lines.append(line)

    # Write output
    out_path = output_path or module_path
    with open(out_path, 'w') as f:
        f.writelines(output_lines)

    print(f"Updated: {out_path}")
    print(f"Added {len(func_map)} function labels")


def main():
    parser = argparse.ArgumentParser(description='Add function labels to SH2 module')
    parser.add_argument('module_file', help='Input module file')
    parser.add_argument('rom_file', help='ROM file for analysis')
    parser.add_argument('--output', '-o', help='Output file (default: overwrite input)')
    args = parser.parse_args()

    add_labels_to_module(args.module_file, args.rom_file, args.output)


if __name__ == '__main__':
    main()
