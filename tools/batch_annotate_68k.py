#!/usr/bin/env python3
"""
Batch annotate all 68K code modules with proper mnemonics and function labels.

Usage:
    python3 batch_annotate_68k.py <rom_file> [--dry-run]
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from annotate_68k_from_rom import M68KModuleAnnotator


# 68K code modules (not data sections)
CODE_MODULE_DIRS = [
    'boot',
    'display',
    'game',
    'hardware-regs',
    'input',
    'main-loop',
    'sound',
]


def main():
    parser = argparse.ArgumentParser(
        description='Batch annotate 68K modules with mnemonics'
    )
    parser.add_argument('rom_file', type=Path, help='ROM file for disassembly')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done')
    parser.add_argument('--module', type=str, help='Only process specific module')
    args = parser.parse_args()

    if not args.rom_file.exists():
        print(f"Error: ROM file {args.rom_file} not found")
        sys.exit(1)

    # Load ROM
    print(f"Loading ROM: {args.rom_file}")
    with open(args.rom_file, 'rb') as f:
        rom_data = f.read()
    print(f"ROM size: {len(rom_data):,} bytes")

    annotator = M68KModuleAnnotator(rom_data)

    # Find module base directory
    modules_dir = Path('disasm/modules/68k')
    if not modules_dir.exists():
        print(f"Error: Modules directory not found: {modules_dir}")
        sys.exit(1)

    total_modules = 0
    total_functions = 0

    for dir_name in CODE_MODULE_DIRS:
        dir_path = modules_dir / dir_name
        if not dir_path.exists():
            continue

        print(f"\n{'='*60}")
        print(f"Processing {dir_name}/")
        print(f"{'='*60}")

        for asm_file in sorted(dir_path.glob('*.asm')):
            if args.module and args.module not in str(asm_file):
                continue

            print(f"\n  {asm_file.name}")

            if args.dry_run:
                print(f"    [DRY RUN] Would annotate {asm_file}")
                total_modules += 1
                continue

            try:
                func_count = annotator.annotate_file(asm_file)
                if func_count:
                    total_functions += func_count
                total_modules += 1
            except Exception as e:
                print(f"    ERROR: {e}")

    print(f"\n{'='*60}")
    print(f"Summary")
    print(f"{'='*60}")
    print(f"Modules processed: {total_modules}")
    print(f"Functions identified: {total_functions}")


if __name__ == '__main__':
    main()
