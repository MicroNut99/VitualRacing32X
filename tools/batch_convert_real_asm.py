#!/usr/bin/env python3
"""
Batch convert annotated DC.W modules to real assembly for the real-asm branch.

This script:
1. Copies annotated modules from modules/68k/ to sections/
2. Converts DC.W + mnemonic comments to real assembly
3. Maps module names to section names
4. Reports conversion statistics

Usage: python batch_convert_real_asm.py [--dry-run]
"""

import os
import sys
import shutil
import re
from pathlib import Path

# Base paths
DISASM_DIR = Path(__file__).parent.parent / "disasm"
MODULES_DIR = DISASM_DIR / "modules" / "68k"
SECTIONS_DIR = DISASM_DIR / "sections"

# Module to section mapping
# Format: (module_subdir, module_pattern, section_pattern)
MODULE_MAPPINGS = [
    # Boot modules
    ("boot", "rom_header.asm", "header.asm"),

    # Game modules - note the naming difference (game_0e200 -> code_e200)
    ("game", "game_0e200.asm", "code_e200.asm"),
    ("game", "game_10200.asm", "code_10200.asm"),
    ("game", "game_12200.asm", "code_12200.asm"),
    ("game", "game_14200.asm", "code_14200.asm"),
    ("game", "game_16200.asm", "code_16200.asm"),

    # Data sections (section_XXXXXX -> code_XXXXXX)
    # These are processed dynamically below
]

def convert_line(line):
    """Convert a single line from DC.W format to mnemonic format."""
    stripped = line.rstrip()

    # Pattern: DC.W $XXXX[,$YYYY...] ; $ADDR MNEMONIC [operands]
    pattern = r'^(\s+)DC\.W\s+\$[0-9A-Fa-f,\$\s]+\s+;\s+(\$[0-9A-Fa-f]+)\s+(.+)$'
    match = re.match(pattern, stripped)

    if match:
        indent = match.group(1)
        address = match.group(2)
        mnemonic = match.group(3).strip()

        # Skip invalid/uncertain decodes
        if not mnemonic or mnemonic.startswith('$') or mnemonic == 'Unknown':
            return line
        if mnemonic.startswith('DC.W'):
            return line
        if '<EA:' in mnemonic:  # Invalid effective address
            return line
        if mnemonic.startswith('MOVEA.W $') and '(A7,' in mnemonic:
            return line  # Suspicious F-line decode

        # Skip instructions that are invalid on 68000
        # BTST can only test Dn or memory, not An
        if re.match(r'BTST\s+D\d,A\d', mnemonic):
            return line  # Invalid: BTST Dn,An
        # BCHG/BCLR/BSET also can't operate on An
        if re.match(r'B(CHG|CLR|SET)\s+.*,A\d$', mnemonic):
            return line

        # Skip problematic patterns
        problem_patterns = [
            'NEGX.B A', 'NEGX.W A', 'NEGX.L A',
            'ORI.B  #', 'ANDI.B  #',
        ]
        if any(pat in mnemonic for pat in problem_patterns):
            return line

        # Skip Line-A ($Axxx) and Line-F ($Fxxx) which are unimplemented on 68000
        if re.match(r'^(MOVE|OR|AND|EOR|ADD|SUB).*#\$[0-9A-Fa-f]+,#', mnemonic):
            return line  # Weird double-immediate - not valid

        return f'{indent}{mnemonic:<40}; {address}\n'

    # Keep other lines unchanged
    return line

def convert_file(src_path, dst_path):
    """Convert a module file to real assembly."""
    with open(src_path, 'r') as f:
        lines = f.readlines()

    converted = [convert_line(line) for line in lines]
    converted_count = sum(1 for orig, conv in zip(lines, converted) if orig != conv)

    with open(dst_path, 'w') as f:
        f.writelines(converted)

    return len(lines), converted_count

def get_data_section_mappings():
    """Generate mappings for all data section files."""
    mappings = []
    data_dir = MODULES_DIR / "data"

    if data_dir.exists():
        for f in sorted(data_dir.glob("section_*.asm")):
            # section_100200.asm -> code_100200.asm
            addr = f.stem.replace("section_", "")
            section_name = f"code_{addr}.asm"
            mappings.append(("data", f.name, section_name))

    return mappings

def main():
    dry_run = "--dry-run" in sys.argv

    # Collect all mappings
    all_mappings = MODULE_MAPPINGS.copy()
    all_mappings.extend(get_data_section_mappings())

    print(f"=== Batch Convert to Real Assembly ===")
    print(f"Source: {MODULES_DIR}")
    print(f"Target: {SECTIONS_DIR}")
    print(f"Mode: {'DRY RUN' if dry_run else 'LIVE'}")
    print(f"Total mappings: {len(all_mappings)}")
    print()

    stats = {
        'converted': 0,
        'skipped': 0,
        'lines_total': 0,
        'lines_converted': 0,
    }

    for subdir, module_name, section_name in all_mappings:
        src = MODULES_DIR / subdir / module_name
        dst = SECTIONS_DIR / section_name

        if not src.exists():
            # print(f"SKIP (not found): {src}")
            stats['skipped'] += 1
            continue

        if dry_run:
            print(f"WOULD: {src.name} -> {dst.name}")
            stats['converted'] += 1
        else:
            lines, converted = convert_file(src, dst)
            print(f"OK: {src.name} -> {dst.name} ({converted}/{lines} lines converted)")
            stats['converted'] += 1
            stats['lines_total'] += lines
            stats['lines_converted'] += converted

    print()
    print(f"=== Summary ===")
    print(f"Files processed: {stats['converted']}")
    print(f"Files skipped: {stats['skipped']}")
    if not dry_run:
        print(f"Total lines: {stats['lines_total']}")
        print(f"Lines converted: {stats['lines_converted']}")

if __name__ == "__main__":
    main()
