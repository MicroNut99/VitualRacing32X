#!/usr/bin/env python3
"""
Convert DC.W format assembly to proper mnemonics.
Handles the specific format from auto-extracted 68K modules.

Usage: python convert_dcw_to_asm.py input.asm [output.asm]
"""
import re
import sys

def convert_line(line):
    """Convert a single line from DC.W format to mnemonic format."""
    stripped = line.rstrip()

    # Pattern: DC.W $XXXX[,$YYYY...] ; $ADDR MNEMONIC [operands]
    # Captures: 1=DC.W values, 2=address, 3=mnemonic+operands
    pattern = r'^(\s+)DC\.W\s+\$[0-9A-Fa-f,\$\s]+\s+;\s+(\$[0-9A-Fa-f]+)\s+(.+)$'
    match = re.match(pattern, stripped)

    if match:
        indent = match.group(1)
        address = match.group(2)
        mnemonic = match.group(3).strip()

        # Check if mnemonic looks valid (not just hex or unknown)
        if mnemonic and not mnemonic.startswith('$') and mnemonic != 'Unknown':
            # Skip problematic mnemonics with invalid 68K syntax
            # (operations on address registers, etc.)
            invalid_patterns = [
                'A4', 'A5', 'A6', 'A7',  # Address reg operations in certain contexts
                'NEGX.B A', 'NEGX.W A', 'NEGX.L A',  # NEGX on A regs
                'ORI.B #', 'ORI.W #', 'ORI.L #',  # ORI immediate (not valid on A regs in some forms)
                'ANDI.B #', 'ANDI.W #', 'ANDI.L #',  # ANDI immediate issues
            ]

            # If mnemonic ends with an A register in wrong context, keep as DC.W
            if any(pat in mnemonic for pat in ['NEGX.B A', 'ORI.B  #', 'ANDI.B  #']):
                return line  # Keep original DC.W format

            # MOVEM with problematic register patterns
            if 'MOVEM' in mnemonic and ('A7' in mnemonic or ',A7' in mnemonic):
                return line  # Keep as DC.W

            return f'{indent}{mnemonic:<40}; {address}\n'

    # Pattern: DC.W $XXXX[,$YYYY...] ; $ADDR (no mnemonic - keep as data)
    pattern_data = r'^(\s+)DC\.W\s+(\$[0-9A-Fa-f,\$\s]+)\s+;\s+(\$[0-9A-Fa-f]+)\s*$'
    match_data = re.match(pattern_data, stripped)

    if match_data:
        # Keep as DC.W (it's data, not code)
        return line

    # Pattern: DC.W values only (from partial conversion files)
    pattern_dcw = r'^(\s+)dc\.w\s+\$[0-9A-Fa-f]+\s+;\s+\$[0-9A-Fa-f]+$'
    if re.match(pattern_dcw, stripped, re.IGNORECASE):
        return line

    # Preserve labels
    if re.match(r'^loc_[0-9A-Fa-f]+:', stripped):
        return line

    # Preserve comments and headers
    if stripped.startswith(';') or stripped == '':
        return line

    # Preserve org directives
    if 'org' in stripped.lower():
        return line

    # Already converted (has mnemonic format)
    if re.match(r'^\s+[A-Z]+', stripped) and '; $' in stripped:
        return line

    # Default: return unchanged
    return line

def convert_file(input_path, output_path=None):
    """Convert entire file."""
    with open(input_path, 'r') as f:
        lines = f.readlines()

    converted = [convert_line(line) for line in lines]

    out_path = output_path or input_path
    with open(out_path, 'w') as f:
        f.writelines(converted)

    print(f"Converted {input_path}: {len(lines)} lines processed")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python convert_dcw_to_asm.py input.asm [output.asm]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    convert_file(input_file, output_file)
