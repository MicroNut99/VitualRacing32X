#!/usr/bin/env python3
"""
Classify data sections by content type.

Analyzes ROM data to identify:
- Palettes (RGB555 color data)
- Graphics/tiles (pixel patterns)
- Geometry (3D vertex/polygon data)
- Lookup tables (repetitive mathematical patterns)
- Executable code (misclassified as data)
- String data
- Compressed data
- Fill/padding

Usage:
    python3 classify_data_sections.py <rom_file> [--apply]
"""

import struct
import re
import sys
import argparse
from pathlib import Path
from collections import Counter


class DataClassifier:
    """Classify ROM data sections by content type."""

    # 68K code signatures
    CODE_OPCODES = {
        0x4E75,  # RTS
        0x4E73,  # RTE
        0x4E71,  # NOP
        0x4EB9,  # JSR abs.l
        0x4EBA,  # JSR (PC)
        0x4EF9,  # JMP abs.l
        0x4EFA,  # JMP (PC)
    }

    # Common 68K instruction patterns
    CODE_PATTERNS = [
        (0xF000, 0x6000),  # Bcc branches
        (0xF100, 0x7000),  # MOVEQ
        (0xFFC0, 0x4E80),  # JSR/JMP indirect
        (0xF1C0, 0x2040),  # MOVEA.L
        (0xF1C0, 0x3040),  # MOVEA.W
    ]

    def __init__(self, rom_data):
        self.rom = rom_data

    def read_words(self, offset, count):
        """Read count 16-bit big-endian words."""
        words = []
        for i in range(count):
            if offset + i*2 + 2 <= len(self.rom):
                w = struct.unpack('>H', self.rom[offset + i*2:offset + i*2 + 2])[0]
                words.append(w)
        return words

    def calculate_entropy(self, data):
        """Calculate data entropy (0-8 bits)."""
        if not data:
            return 0
        counts = Counter(data)
        total = len(data)
        entropy = 0
        for count in counts.values():
            if count > 0:
                p = count / total
                entropy -= p * (p.bit_length() - 1 if p > 0 else 0)
        # Simplified: use unique ratio as proxy
        return len(counts) / min(256, total) * 8

    def detect_code(self, offset, size):
        """Detect if section contains 68K executable code."""
        words = self.read_words(offset, min(size // 2, 64))  # Check first 64 words

        # Count specific high-confidence code markers
        rts_count = sum(1 for w in words if w == 0x4E75)  # RTS
        jsr_count = sum(1 for w in words if w in (0x4EBA, 0x4EB9))  # JSR
        bcc_count = sum(1 for w in words if (w & 0xF000) == 0x6000)  # Bcc

        # Calculate score with heavier weights for definitive code markers
        score = rts_count * 10 + jsr_count * 8 + bcc_count * 2

        # Require high confidence (multiple RTS or JSR instructions)
        return score >= 40  # Much stricter threshold

    def detect_palette(self, offset, size):
        """Detect RGB555 palette data."""
        words = self.read_words(offset, min(size // 2, 64))

        # Palettes typically:
        # - Have first entry as 0x0000 (transparent) or background
        # - Values usually < 0x8000 (no priority bit) or consistent priority
        # - Reasonable color distribution

        if not words:
            return False, 0

        rgb555_count = sum(1 for w in words if w < 0x8000)
        zero_count = sum(1 for w in words if w == 0)

        # Check for palette-like structure (32 or 64 entry blocks)
        is_palette = (
            rgb555_count > len(words) * 0.8 and
            zero_count < len(words) * 0.5 and
            len(set(words)) > 8  # Some color variety
        )

        return is_palette, rgb555_count / len(words)

    def detect_geometry(self, offset, size):
        """Detect 3D geometry data (vertices, polygons)."""
        words = self.read_words(offset, min(size // 2, 256))

        if not words:
            return False

        # Geometry patterns:
        # - Coordinate values often in range -32768 to 32767 (signed 16-bit)
        # - May have structure like: count, x, y, z repeating
        # - Often has small integers for indices

        signed_like = sum(1 for w in words if 0x8000 <= w <= 0xFFFF or w < 0x1000)
        small_ints = sum(1 for w in words if w < 0x100)

        # Look for vertex-like patterns (sets of 3 values)
        return signed_like > len(words) * 0.4 and small_ints > len(words) * 0.2

    def detect_lookup_table(self, offset, size):
        """Detect lookup tables (sine, cosine, etc.)."""
        words = self.read_words(offset, min(size // 2, 256))

        if len(words) < 32:
            return False, None

        # Check for repetitive patterns
        unique_ratio = len(set(words)) / len(words)

        # Highly repetitive (same value repeated)
        if unique_ratio < 0.1:
            return True, "fill_pattern"

        # Check for monotonic sequences (sorted tables)
        increasing = sum(1 for i in range(1, len(words)) if words[i] >= words[i-1])
        decreasing = sum(1 for i in range(1, len(words)) if words[i] <= words[i-1])

        if increasing > len(words) * 0.8 or decreasing > len(words) * 0.8:
            return True, "sorted_table"

        # Check for periodic patterns (like sine waves)
        # Look for sign changes that might indicate oscillation
        sign_changes = sum(1 for i in range(1, len(words))
                         if (words[i] >= 0x8000) != (words[i-1] >= 0x8000))
        if sign_changes > 4:
            return True, "periodic_table"

        return False, None

    def detect_compressed(self, offset, size):
        """Detect potentially compressed data."""
        data = self.rom[offset:offset + min(size, 256)]

        # High entropy suggests compression
        unique_bytes = len(set(data))
        entropy_ratio = unique_bytes / min(256, len(data))

        return entropy_ratio > 0.7

    def detect_string_table(self, offset, size):
        """Detect ASCII string data."""
        data = self.rom[offset:offset + min(size, 256)]

        printable = sum(1 for b in data if 32 <= b <= 126 or b in (0, 10, 13))
        return printable > len(data) * 0.7

    def classify_section(self, offset, size):
        """Classify a data section."""

        # Check for code first (highest priority)
        if self.detect_code(offset, size):
            return "CODE", "Contains 68K executable code (misclassified)"

        # Check for lookup tables
        is_lut, lut_type = self.detect_lookup_table(offset, size)
        if is_lut:
            if lut_type == "fill_pattern":
                return "FILL", "Fill pattern or padding data"
            elif lut_type == "sorted_table":
                return "LUT_SORTED", "Sorted lookup table"
            elif lut_type == "periodic_table":
                return "LUT_TRIG", "Trigonometric or periodic lookup table"

        # Check for palette
        is_palette, confidence = self.detect_palette(offset, size)
        if is_palette:
            return "PALETTE", f"RGB555 color palette data ({confidence:.0%} RGB555)"

        # Check for geometry
        if self.detect_geometry(offset, size):
            return "GEOMETRY", "3D geometry data (vertices/polygons)"

        # Check for strings
        if self.detect_string_table(offset, size):
            return "STRINGS", "ASCII string table"

        # Check for compressed
        if self.detect_compressed(offset, size):
            return "COMPRESSED", "Compressed or high-entropy graphics data"

        return "DATA", "Unclassified data section"

    def get_section_label(self, classification):
        """Get an appropriate label for the classification."""
        labels = {
            "CODE": "68K Code (Misclassified)",
            "PALETTE": "Color Palette",
            "GEOMETRY": "3D Geometry",
            "LUT_SORTED": "Lookup Table",
            "LUT_TRIG": "Trigonometric Table",
            "FILL": "Fill Pattern",
            "COMPRESSED": "Compressed Graphics",
            "STRINGS": "String Table",
            "DATA": "Game Data",
        }
        return labels.get(classification, "Data")


def analyze_data_modules(rom_path, modules_dir, apply_labels=False):
    """Analyze all data modules and optionally apply labels."""

    with open(rom_path, 'rb') as f:
        rom_data = f.read()

    classifier = DataClassifier(rom_data)

    data_dir = Path(modules_dir) / '68k' / 'data'
    if not data_dir.exists():
        print(f"Error: Data directory not found: {data_dir}")
        return

    # Collect statistics
    stats = Counter()
    results = []

    for asm_file in sorted(data_dir.glob('*.asm')):
        # Parse org address from file
        with open(asm_file, 'r') as f:
            content = f.read()

        match = re.search(r'org\s+\$([0-9A-Fa-f]+)', content)
        if not match:
            continue

        org_addr = int(match.group(1), 16)

        # Get section size from header or estimate
        size_match = re.search(r'Address:.*\((\d+) bytes\)', content)
        if size_match:
            size = int(size_match.group(1))
        else:
            size = 8192  # Default

        # Classify
        classification, description = classifier.classify_section(org_addr, size)
        stats[classification] += 1
        results.append((asm_file, org_addr, size, classification, description))

    # Print summary
    print("=" * 70)
    print("Data Section Classification Summary")
    print("=" * 70)
    for cls, count in sorted(stats.items(), key=lambda x: -x[1]):
        print(f"  {cls:15s}: {count:3d} sections")
    print(f"  {'TOTAL':15s}: {sum(stats.values()):3d} sections")
    print()

    # Print details for interesting sections
    print("=" * 70)
    print("Sections Containing Code (need reclassification)")
    print("=" * 70)
    code_sections = [r for r in results if r[3] == "CODE"]
    for asm_file, addr, size, cls, desc in code_sections[:20]:
        print(f"  ${addr:06X}: {asm_file.name}")
    if len(code_sections) > 20:
        print(f"  ... and {len(code_sections) - 20} more")
    print()

    if apply_labels:
        print("=" * 70)
        print("Applying labels to data sections...")
        print("=" * 70)
        apply_section_labels(results, classifier)

    return results, stats


def apply_section_labels(results, classifier):
    """Apply classification labels to data section files."""

    updated = 0
    for asm_file, addr, size, classification, description in results:
        with open(asm_file, 'r') as f:
            lines = f.readlines()

        # Find the header section and update it
        new_lines = []
        in_header = False
        header_updated = False

        for i, line in enumerate(lines):
            # Look for the TODO line to replace
            if 'TODO: Add function annotations' in line and not header_updated:
                label = classifier.get_section_label(classification)
                new_lines.append(f"; Data Type: {label}\n")
                new_lines.append(f"; Classification: {classification}\n")
                new_lines.append(f"; {description}\n")
                new_lines.append(";\n")
                header_updated = True
            else:
                new_lines.append(line)

        if header_updated:
            with open(asm_file, 'w') as f:
                f.writelines(new_lines)
            updated += 1

    print(f"Updated {updated} section files")


def main():
    parser = argparse.ArgumentParser(description='Classify data sections')
    parser.add_argument('rom_file', type=Path, help='ROM file')
    parser.add_argument('--modules-dir', type=Path, default=Path('disasm/modules'),
                       help='Modules directory')
    parser.add_argument('--apply', action='store_true', help='Apply labels to files')
    args = parser.parse_args()

    if not args.rom_file.exists():
        print(f"Error: ROM file not found: {args.rom_file}")
        sys.exit(1)

    analyze_data_modules(args.rom_file, args.modules_dir, args.apply)


if __name__ == '__main__':
    main()
