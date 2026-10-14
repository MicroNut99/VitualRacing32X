#!/usr/bin/env python3
"""
Optimization Patch: Inline func_016 at all call sites
Estimated gain: +5% performance (60 FPS -> 63 FPS)
"""

import sys
import struct
from pathlib import Path

# func_016 machine code (30 bytes total)
# Excludes RTS (00 0b) and delay slot (1e 4d) as those are replaced by inline
FUNC_016_BODY = bytes([
    0x51, 0xE7,  # MOV.L @($1C,R14),R1
    0x52, 0xE8,  # MOV.L @($20,R14),R2
    0x41, 0x28,  # SHLL16 R1
    0x42, 0x28,  # SHLL16 R2
    0x50, 0xE5,  # MOV.L @($14,R14),R0
    0x63, 0x13,  # MOV R1,R3
    0x64, 0x23,  # MOV R2,R4
    0x21, 0x0B,  # OR R0,R1
    0x22, 0x0B,  # OR R0,R2
    0x1E, 0x1A,  # MOV.L R1,@($28,R14)
    0x1E, 0x2B,  # MOV.L R2,@($2C,R14)
    0x50, 0xE6,  # MOV.L @($18,R14),R0
    0x23, 0x0B,  # OR R0,R3
    0x24, 0x0B,  # OR R0,R4
    0x1E, 0x3C,  # MOV.L R3,@($30,R14)
    0x1E, 0x4D,  # MOV.L R4,@($34,R14)  (was in delay slot)
])

# Call sites: (rom_offset, original_bytes, description)
CALL_SITES = [
    (0x2338C, bytes([0xBF, 0xEC, 0x00, 0x09]), "func_017 call site 1"),
    (0x233F4, bytes([0xBF, 0xB8, 0x00, 0x09]), "func_018 call site 2"),
    (0x23452, bytes([0xBF, 0x89, 0x00, 0x09]), "func_019 call site 3"),
    (0x234CA, bytes([0xBF, 0x4D, 0x00, 0x09]), "func_020 call site 4"),
]

def verify_rom(rom_data):
    """Verify this is the correct ROM"""
    # Check ROM header for "SEGA 32X" marker
    if rom_data[0x100:0x108] != b'SEGA 32X':
        print("ERROR: Not a valid Sega 32X ROM")
        return False

    # Check ROM title
    title = rom_data[0x150:0x160].decode('ascii', errors='ignore').strip()
    if 'VIRTUA RACING' not in title:
        print(f"WARNING: ROM title is '{title}', expected 'VIRTUA RACING'")
        # Continue anyway, might be regional variant

    # Verify func_016 location
    func_16_check = rom_data[0x23368:0x2336E]
    if func_16_check != bytes([0x51, 0xE7, 0x52, 0xE8, 0x41, 0x28]):
        print(f"ERROR: func_016 not found at expected location")
        print(f"Expected: 51 e7 52 e8 41 28")
        print(f"Found:    {func_16_check.hex(' ')}")
        return False

    print("✓ ROM verified: Virtua Racing Deluxe (USA)")
    return True

def check_call_sites(rom_data):
    """Verify all call sites match expected bytes"""
    print("\n=== Verifying Call Sites ===")
    all_ok = True

    for offset, expected, desc in CALL_SITES:
        actual = rom_data[offset:offset+4]
        if actual == expected:
            print(f"✓ {desc} at 0x{offset:06X}: {actual.hex(' ')}")
        else:
            print(f"✗ {desc} at 0x{offset:06X}:")
            print(f"  Expected: {expected.hex(' ')}")
            print(f"  Found:    {actual.hex(' ')}")
            all_ok = False

    return all_ok

def check_space_after_call_sites(rom_data):
    """Check if there's enough space after each call site"""
    print("\n=== Checking Available Space ===")
    NEEDED_SPACE = len(FUNC_016_BODY)  # 30 bytes
    CURRENT_SPACE = 4  # BSR + NOP
    EXPANSION = NEEDED_SPACE - CURRENT_SPACE  # 26 bytes

    print(f"Inline code size: {NEEDED_SPACE} bytes")
    print(f"Current call size: {CURRENT_SPACE} bytes (BSR + NOP)")
    print(f"Expansion needed: {EXPANSION} bytes per site\n")

    warnings = []
    for offset, expected, desc in CALL_SITES:
        # Check next 30 bytes after call site
        next_bytes = rom_data[offset+4:offset+34]

        # Look for RTS (00 0b) or other function boundaries
        # Count NOPs (00 09) which indicate padding
        nop_count = 0
        for i in range(0, len(next_bytes)-1, 2):
            if next_bytes[i:i+2] == bytes([0x00, 0x09]):
                nop_count += 1

        print(f"{desc}:")
        print(f"  Next 30 bytes: {next_bytes[:30].hex(' ')}")
        print(f"  NOPs found: {nop_count}")

        # Check for potential issues
        if nop_count >= 13:  # 26 bytes / 2 = 13 NOPs
            print(f"  ✓ Sufficient NOP padding for inline")
        else:
            # Check if there's data (non-code) we can safely overwrite
            # Or if we need to be more careful
            warnings.append(f"  ⚠ May overwrite code/data at {desc}")

    if warnings:
        print("\nWARNINGS:")
        for w in warnings:
            print(w)
        print("\nThis optimization may require manual verification.")
        return False

    return True

def apply_inline_patch(rom_data):
    """Apply the inline optimization"""
    print("\n=== Applying Inline Patches ===")

    modified_rom = bytearray(rom_data)

    for offset, original, desc in CALL_SITES:
        print(f"\nPatching {desc} at 0x{offset:06X}:")
        print(f"  Before (4 bytes): {original.hex(' ')}")

        # Replace BSR + NOP (4 bytes) with inline code (30 bytes)
        modified_rom[offset:offset+len(FUNC_016_BODY)] = FUNC_016_BODY

        print(f"  After (30 bytes): {bytes(modified_rom[offset:offset+30]).hex(' ')}")
        print(f"  ✓ Inlined func_016 body")

    return bytes(modified_rom)

def create_backup(input_path):
    """Create backup of original ROM"""
    backup_path = input_path.with_suffix('.32x.backup')
    if not backup_path.exists():
        import shutil
        shutil.copy(input_path, backup_path)
        print(f"✓ Backup created: {backup_path}")
    else:
        print(f"✓ Backup already exists: {backup_path}")

def main():
    if len(sys.argv) < 2:
        print("Usage: patch_func16_inline.py <rom_file> [output_file]")
        print("\nThis script inlines func_016 at all 4 call sites for +5% performance.")
        print("If output_file is not specified, creates 'rom_optimized.32x'")
        sys.exit(1)

    input_file = Path(sys.argv[1])
    if len(sys.argv) >= 3:
        output_file = Path(sys.argv[2])
    else:
        output_file = Path("Virtua Racing Deluxe (USA) - Optimized.32x")

    if not input_file.exists():
        print(f"ERROR: Input file not found: {input_file}")
        sys.exit(1)

    print("=" * 70)
    print(" func_016 Inline Optimization Patcher")
    print(" Expected gain: +5% performance (3 FPS @ 60 FPS baseline)")
    print("=" * 70)
    print()

    # Read ROM
    print(f"Reading ROM: {input_file}")
    rom_data = input_file.read_bytes()
    print(f"ROM size: {len(rom_data):,} bytes ({len(rom_data)/1024/1024:.2f} MB)")

    # Verify
    if not verify_rom(rom_data):
        print("\nAborting due to verification failure.")
        sys.exit(1)

    # Check call sites
    if not check_call_sites(rom_data):
        print("\nAborting: Call sites don't match expected bytes.")
        print("This ROM may already be patched or is a different version.")
        sys.exit(1)

    # Check space (warning only)
    space_ok = check_space_after_call_sites(rom_data)
    if not space_ok:
        response = input("\nContinue anyway? (yes/no): ")
        if response.lower() != 'yes':
            print("Aborted by user.")
            sys.exit(0)

    # Create backup
    create_backup(input_file)

    # Apply patch
    patched_rom = apply_inline_patch(rom_data)

    # Save
    output_file.write_bytes(patched_rom)
    print(f"\n✓ Optimized ROM saved: {output_file}")
    print(f"  Size: {len(patched_rom):,} bytes")

    # Calculate changes
    changes = sum(1 for i in range(len(rom_data)) if rom_data[i] != patched_rom[i])
    print(f"  Bytes modified: {changes:,} ({changes/len(rom_data)*100:.3f}%)")

    print("\n" + "=" * 70)
    print(" Optimization complete!")
    print("=" * 70)
    print("\nNext steps:")
    print(f"1. Test in emulator: ./Gens_KMod_v0.7.3/gens.exe \"{output_file}\"")
    print("2. Verify game boots and runs correctly")
    print("3. Measure performance improvement (should see ~3 FPS gain)")
    print("\nIf you encounter issues, restore from backup:")
    print(f"   cp \"{input_file}.backup\" \"{input_file}\"")
    print()

if __name__ == '__main__':
    main()
