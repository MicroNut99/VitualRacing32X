#!/usr/bin/env python3
"""
Convert all misclassified CODE sections in data/ directory to proper assembly.
"""

import subprocess
from pathlib import Path

# All code sections that need conversion (found via grep "Classification: CODE")
CODE_SECTIONS = [
    "section_100200.asm",
    "section_102200.asm",
    "section_104200.asm",
    "section_106200.asm",
    "section_108200.asm",
    "section_10c200.asm",
    "section_10e200.asm",
    "section_118200.asm",
    "section_11a200.asm",
    "section_11c200.asm",
    "section_11e200.asm",
    "section_124200.asm",
    "section_154200.asm",
    "section_17a200.asm",
    "section_1e4200.asm",
    "section_220200.asm",
    "section_22200.asm",
    "section_228200.asm",
    "section_264200.asm",
    "section_266200.asm",
    "section_268200.asm",
    "section_26a200.asm",
    "section_26c200.asm",
    "section_26e200.asm",
    "section_270200.asm",
    "section_272200.asm",
    "section_274200.asm",
    "section_276200.asm",
    "section_2a0200.asm",
    "section_2a6200.asm",
    "section_2aa200.asm",
    "section_2ac200.asm",
    "section_2ae200.asm",
    "section_2b0200.asm",
    "section_2b2200.asm",
    "section_2b4200.asm",
    "section_2e8200.asm",
    "section_2ea200.asm",
    "section_2ec200.asm",
    "section_2ee200.asm",
    "section_30200.asm",
    "section_32200.asm",
    "section_42200.asm",
    "section_44200.asm",
    "section_46200.asm",
    "section_4a200.asm",
    "section_4e200.asm",
    "section_50200.asm",
    "section_52200.asm",
    "section_54200.asm",
    "section_56200.asm",
    "section_58200.asm",
    "section_5c200.asm",
    "section_62200.asm",
    "section_64200.asm",
    "section_66200.asm",
    "section_68200.asm",
    "section_6a200.asm",
    "section_6e200.asm",
    "section_72200.asm",
    "section_7a200.asm",
    "section_a6200.asm",
    "section_f0200.asm",
    "section_f2200.asm",
    "section_f4200.asm",
]

def main():
    repo_root = Path(__file__).parent.parent
    data_dir = repo_root / "disasm" / "modules" / "68k" / "data"
    rom_file = repo_root / "Virtua Racing Deluxe (USA).32x"
    disasm_tool = repo_root / "tools" / "disasm_to_asm.py"

    if not rom_file.exists():
        print(f"Error: ROM file not found at {rom_file}")
        return 1

    if not disasm_tool.exists():
        print(f"Error: Disassembly tool not found at {disasm_tool}")
        return 1

    print(f"Converting {len(CODE_SECTIONS)} code sections...")
    print(f"ROM: {rom_file}")
    print(f"Data directory: {data_dir}")
    print()

    success_count = 0
    error_count = 0

    for i, section_file in enumerate(CODE_SECTIONS, 1):
        module_path = data_dir / section_file

        if not module_path.exists():
            print(f"[{i:2d}/{len(CODE_SECTIONS)}] ⚠️  NOT FOUND: {section_file}")
            error_count += 1
            continue

        try:
            # Run disasm_to_asm.py with --dcw flag for byte-exact output
            cmd = [
                "python3",
                str(disasm_tool),
                str(rom_file),
                "--module", str(module_path),
                "--dcw"
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

            if result.returncode == 0:
                print(f"[{i:2d}/{len(CODE_SECTIONS)}] ✓ {section_file}")
                success_count += 1
            else:
                print(f"[{i:2d}/{len(CODE_SECTIONS)}] ✗ {section_file}: {result.stderr.strip()}")
                error_count += 1

        except subprocess.TimeoutExpired:
            print(f"[{i:2d}/{len(CODE_SECTIONS)}] ✗ {section_file}: Timeout")
            error_count += 1
        except Exception as e:
            print(f"[{i:2d}/{len(CODE_SECTIONS)}] ✗ {section_file}: {e}")
            error_count += 1

    print()
    print(f"Conversion complete:")
    print(f"  Success: {success_count}")
    print(f"  Errors:  {error_count}")
    print(f"  Total:   {len(CODE_SECTIONS)}")

    return 0 if error_count == 0 else 1

if __name__ == '__main__':
    exit(main())
