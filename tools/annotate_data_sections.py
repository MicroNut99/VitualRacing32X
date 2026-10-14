#!/usr/bin/env python3
"""
Analyze and annotate data sections in the disassembly.
Identifies data types and adds descriptive headers.
"""

import re
import os
from pathlib import Path
from collections import Counter

SECTIONS_DIR = Path(__file__).parent.parent / "disasm" / "sections"

# Known data section types based on address ranges and patterns
KNOWN_DATA_REGIONS = {
    # Format: (start_addr, end_addr): (type, description)
    (0x012E00, 0x014200): ("lookup_tables", "Trigonometry and math lookup tables"),
    (0x014200, 0x016200): ("object_tables", "Object parameter tables"),
    (0x016200, 0x018200): ("sprite_data", "Sprite definition data"),
    (0x018200, 0x020200): ("graphics_data", "Compressed graphics data"),
    (0x020200, 0x024200): ("level_data", "Track/level layout data"),
    (0x024200, 0x028200): ("ai_data", "AI behavior and waypoint data"),
    (0x028200, 0x030200): ("sound_data", "Sound effect data"),
    (0x030200, 0x032200): ("music_code", "Z80 sound driver code"),
    (0x032200, 0x080200): ("track_graphics", "Track graphics and textures"),
    (0x080200, 0x0C0200): ("sprite_graphics", "Sprite graphics data"),
    (0x0C0200, 0x100200): ("model_data", "3D model vertex data"),
    (0x100200, 0x140200): ("texture_data", "Texture and palette data"),
    (0x140200, 0x180200): ("additional_graphics", "Additional graphics"),
    (0x180200, 0x200200): ("track_data_2", "Extended track data"),
    (0x200200, 0x280200): ("compressed_data", "Compressed asset data"),
    (0x280200, 0x2C0200): ("audio_samples", "PCM audio samples"),
    (0x2C0200, 0x300200): ("padding_or_unused", "Padding/unused space"),
}


def analyze_data_patterns(filepath):
    """Analyze data patterns in a section file."""
    with open(filepath, 'r') as f:
        lines = f.readlines()

    # Count data values
    values = []
    for line in lines:
        match = re.search(r'dc\.w\s+\$([0-9A-Fa-f]+)', line)
        if match:
            values.append(int(match.group(1), 16))

    if not values:
        return None

    stats = {
        'total': len(values),
        'unique': len(set(values)),
        'zeros': values.count(0),
        'ffff': values.count(0xFFFF),
        'small_values': sum(1 for v in values if v < 0x100),
        'pointer_like': sum(1 for v in values if 0x8000 <= v <= 0xFFFF or 0x0200 <= v <= 0x2000),
    }

    # Determine likely data type
    if stats['ffff'] > stats['total'] * 0.9:
        stats['likely_type'] = 'padding'
        stats['description'] = 'Unused/padding (mostly $FFFF)'
    elif stats['zeros'] > stats['total'] * 0.5:
        stats['likely_type'] = 'sparse_data'
        stats['description'] = 'Sparse data (many zeros)'
    elif stats['unique'] < stats['total'] * 0.1:
        stats['likely_type'] = 'repetitive'
        stats['description'] = 'Repetitive/compressed data'
    elif stats['small_values'] > stats['total'] * 0.7:
        stats['likely_type'] = 'byte_data'
        stats['description'] = 'Byte-oriented data (graphics/tiles)'
    elif stats['pointer_like'] > stats['total'] * 0.3:
        stats['likely_type'] = 'pointer_table'
        stats['description'] = 'Pointer/offset table'
    else:
        stats['likely_type'] = 'mixed_data'
        stats['description'] = 'Mixed binary data'

    return stats


def get_section_addr(filename):
    """Extract section start address from filename."""
    match = re.search(r'code_([0-9a-f]+)\.asm', filename.lower())
    if match:
        return int(match.group(1), 16)
    return None


def get_known_description(addr):
    """Get known description for address range."""
    for (start, end), (dtype, desc) in KNOWN_DATA_REGIONS.items():
        if start <= addr < end:
            return dtype, desc
    return None, None


def annotate_section(filepath, dry_run=False):
    """Add annotation header to a data section."""
    addr = get_section_addr(filepath.name)
    if addr is None:
        return False

    # Check if it's a data-only section
    with open(filepath, 'r') as f:
        content = f.read()

    # Skip if already has code (mnemonics)
    if re.search(r'\b(MOVE|JSR|RTS|BRA|LEA|ADD|SUB)\b', content):
        return False

    # Skip if already annotated
    if '; Data Type:' in content:
        return False

    # Analyze patterns
    stats = analyze_data_patterns(filepath)
    if not stats:
        return False

    # Get known description or use analyzed one
    known_type, known_desc = get_known_description(addr)
    if known_desc:
        data_type = known_type
        description = known_desc
    else:
        data_type = stats['likely_type']
        description = stats['description']

    # Build annotation header
    annotation = f"""; ----------------------------------------------------------------------------
; Data Type: {data_type}
; Description: {description}
; Statistics: {stats['total']} words, {stats['unique']} unique values
;             {stats['zeros']} zeros, {stats['ffff']} $FFFF values
; ----------------------------------------------------------------------------

"""

    # Insert after the original header (after first blank line or org)
    lines = content.split('\n')
    insert_pos = 0
    for i, line in enumerate(lines):
        if line.strip().startswith('org') or (line.strip() == '' and i > 3):
            insert_pos = i + 1
            break

    if insert_pos == 0:
        insert_pos = 6  # Default position after standard header

    new_lines = lines[:insert_pos] + [''] + annotation.split('\n') + lines[insert_pos:]
    new_content = '\n'.join(new_lines)

    if not dry_run:
        with open(filepath, 'w') as f:
            f.write(new_content)

    return True


def main():
    import sys
    dry_run = '--dry-run' in sys.argv

    print(f"=== Data Section Annotation {'(DRY RUN)' if dry_run else ''} ===")
    print(f"Scanning: {SECTIONS_DIR}")
    print()

    annotated = 0
    skipped_code = 0
    skipped_annotated = 0

    for filepath in sorted(SECTIONS_DIR.glob("code_*.asm")):
        addr = get_section_addr(filepath.name)
        if addr is None:
            continue

        with open(filepath, 'r') as f:
            content = f.read()

        # Check section type
        has_code = bool(re.search(r'\b(MOVE|JSR|RTS|BRA|LEA)\b', content))
        already_annotated = '; Data Type:' in content

        if has_code:
            skipped_code += 1
            continue

        if already_annotated:
            skipped_annotated += 1
            continue

        # Analyze and annotate
        stats = analyze_data_patterns(filepath)
        if stats:
            known_type, known_desc = get_known_description(addr)
            desc = known_desc if known_desc else stats['description']

            if annotate_section(filepath, dry_run):
                annotated += 1
                action = "Would annotate" if dry_run else "Annotated"
                print(f"{action}: {filepath.name} - {desc}")

    print()
    print(f"=== Summary ===")
    print(f"Data sections annotated: {annotated}")
    print(f"Code sections skipped: {skipped_code}")
    print(f"Already annotated: {skipped_annotated}")

    if dry_run:
        print("\nRun without --dry-run to apply changes")


if __name__ == "__main__":
    main()
