#!/usr/bin/env python3
"""
Find and analyze jump tables in M68000 ROM

Jump table patterns (M68000):
- Load table address: LEA table_addr,A1  (0x43F9 xxxx xxxx)
- Load entry: MOVEA.L (A1,D0.W),A1       (0x2271 0000)
- Jump: JMP (A1)                         (0x4ED1)
- Jump: JSR (A1)                         (0x4E91)

This tool:
1. Finds likely jump table locations by pattern scanning
2. Extracts all handler addresses from each table
3. Cross-references against known functions
4. Outputs new/undocumented handlers
"""

import struct
import sys
from pathlib import Path
from collections import defaultdict, OrderedDict

# Known jump table locations from manual analysis
# Table addresses are CPU addresses (0x00880000-based)
# We convert to file offsets by subtracting 0x00880000
KNOWN_TABLES = {
    0x7BF6: {  # func_7BE4 dispatcher
        'entries': 16,
        'dispatcher': 0x7BE4,
        'name': 'func_7BE4_dispatcher_table',
        'entry_size': 4,
    },
    0x14888: {  # func_BA18 dispatcher 1 (CPU $00894888)
        'entries': 16,
        'dispatcher': 0xBA18,
        'name': 'func_BA18_table_1',
        'entry_size': 4,
    },
    0x14C88: {  # func_BA18 dispatcher 2 (CPU $00894C88)
        'entries': 16,
        'dispatcher': 0xBA18,
        'name': 'func_BA18_table_2',
        'entry_size': 4,
    },
    0x15088: {  # func_BA18 dispatcher 3 (CPU $00895088)
        'entries': 16,
        'dispatcher': 0xBA18,
        'name': 'func_BA18_table_3',
        'entry_size': 4,
    },
}

def read_rom(rom_path):
    """Load ROM file"""
    with open(rom_path, 'rb') as f:
        return f.read()

def extract_table_entries(rom_data, table_offset, num_entries=16, entry_size=4):
    """
    Extract handler addresses from a jump table

    Args:
        rom_data: ROM binary
        table_offset: File offset of table start
        num_entries: Number of entries in table
        entry_size: Size per entry (usually 4 for long addresses)

    Returns:
        List of handler addresses (as 32-bit values)
    """
    entries = []

    for i in range(num_entries):
        offset = table_offset + (i * entry_size)
        if offset + entry_size > len(rom_data):
            break

        # Read as big-endian 32-bit address
        addr = struct.unpack('>I', rom_data[offset:offset+4])[0]
        entries.append({
            'index': i,
            'file_offset': offset,
            'cpu_address': addr,
            'display_addr': f"${addr:08X}" if addr < 0x100000 else f"${addr:08X}",
        })

    return entries

def convert_file_offset_to_cpu(file_offset):
    """Convert ROM file offset to M68000 CPU address"""
    return file_offset + 0x00880000

def find_potential_tables(rom_data, start=0x4000, end=None, min_entries=8, region_name=""):
    """
    Scan ROM for potential jump table patterns

    Looks for:
    - Sequences of valid 4-byte function pointers
    - Valid 68K address range (0x00880000-0x008FFFFF)
    - At least min_entries consecutive valid entries suggests a jump table

    Args:
        rom_data: ROM binary data
        start: File offset to start scanning
        end: File offset to end scanning (default: start + 0xC000)
        min_entries: Minimum consecutive entries to qualify as table (default: 8)
        region_name: Name for this region (for display)
    """
    if end is None:
        end = min(start + 0xC000, len(rom_data))

    tables = {}

    for base_offset in range(start, end - 32, 4):
        # Check if this looks like a jump table
        candidate_addrs = []
        for i in range(64):  # Check up to 64 entries
            offset = base_offset + (i * 4)
            if offset + 4 > len(rom_data):
                break
            addr = struct.unpack('>I', rom_data[offset:offset+4])[0]

            # Valid 68K code address range (entire ROM space)
            if 0x00880000 <= addr <= 0x008FFFFF:
                candidate_addrs.append((i, addr, offset))
            else:
                break  # Stop at first invalid address

        # If we found enough consecutive valid addresses, might be a jump table
        if len(candidate_addrs) >= min_entries:
            # Verify it looks like actual code by sampling
            sample_addr = candidate_addrs[0][1]
            sample_offset = sample_addr - 0x00880000
            if 0 <= sample_offset < len(rom_data):
                opcode = struct.unpack('>H', rom_data[sample_offset:sample_offset+2])[0]
                # Check if it looks like code (not obviously random data)
                # Extended opcode patterns for better detection
                is_code = (opcode in [0x4E75, 0x4E56, 0x48E7, 0x4CDF, 0x4E71] or
                          (opcode & 0xFF00) == 0x7000 or  # MOVEQ
                          (opcode & 0xFFC0) == 0x4E80 or  # JSR/JMP patterns
                          (opcode & 0xF000) == 0x6000 or  # Bcc branches
                          (opcode & 0xF100) == 0x3000 or  # MOVE.W
                          (opcode & 0xF100) == 0x2000)    # MOVE.L

                if is_code:
                    unique_addrs = len(set(addr for _, addr, _ in candidate_addrs))
                    # Only record if we have meaningful variety (not all same address)
                    if unique_addrs >= 2:
                        table_id = f"table_{base_offset:06X}"
                        tables[table_id] = {
                            'offset': base_offset,
                            'cpu_addr': base_offset + 0x00880000,
                            'entries': candidate_addrs,
                            'unique_handlers': unique_addrs,
                            'region': region_name,
                        }

    return tables


# Priority 9 region definitions
PRIORITY_9_REGIONS = [
    {'name': 'Main Code 2', 'start': 0x10000, 'end': 0x20000, 'min_entries': 4},
    {'name': 'Extended Low', 'start': 0x30000, 'end': 0x50000, 'min_entries': 4},
    {'name': 'Extended Mid', 'start': 0x50000, 'end': 0x80000, 'min_entries': 4},
    {'name': 'Extended High', 'start': 0x80000, 'end': 0xC0000, 'min_entries': 4},
]

def analyze_known_tables(rom_data):
    """Extract handlers from known jump tables"""
    results = {}

    for table_offset, info in KNOWN_TABLES.items():
        print(f"\n=== {info['name']} ===")
        print(f"Location: ${table_offset:06X} (file) / ${table_offset + 0x880000:08X} (CPU)")
        print(f"Dispatcher: func @ ${info['dispatcher']:06X}")
        print(f"Entries: {info['entries']}\n")

        entries = extract_table_entries(
            rom_data,
            table_offset,
            info['entries'],
            info['entry_size']
        )

        results[info['name']] = {
            'location': table_offset,
            'dispatcher': info['dispatcher'],
            'entries': entries,
            'info': info,
        }

        # Print entries
        print(f"{'Index':<6} {'File Offset':<12} {'CPU Address':<12} {'Symbol':<20}")
        print("-" * 50)

        handler_addrs = set()
        for entry in entries:
            # Convert to function name format
            file_offset = entry['cpu_address'] - 0x00880000
            func_name = f"func_{file_offset:X}"
            print(f"{entry['index']:<6} ${entry['file_offset']:06X}       ${entry['cpu_address']:08X}       {func_name:<20}")
            handler_addrs.add(entry['cpu_address'])

        results[info['name']]['handler_addresses'] = handler_addrs

    return results

def load_documented_functions(annotation_file):
    """Load documented function addresses from annotation file"""
    documented = set()

    try:
        with open(annotation_file, 'r') as f:
            content = f.read()

        # Extract addresses in format $XXXXX from documentation
        import re
        # Pattern: $ followed by hex digits (address)
        pattern = r'\$([0-9A-F]+)'
        matches = re.findall(pattern, content, re.IGNORECASE)

        for match in matches:
            try:
                addr = int(match, 16)
                # Only track 68K addresses (with 0x00880000 base)
                if 0x880000 <= addr <= 0x8FFFFF:
                    documented.add(addr)
            except ValueError:
                pass
    except FileNotFoundError:
        print(f"Warning: Could not find {annotation_file}")

    return documented

def main():
    rom_path = Path('/mnt/data/src/32x-playground/build/vr_rebuild.32x')
    annotation_file = Path('/mnt/data/src/32x-playground/analysis/68K_MAIN_LOGIC.md')

    if not rom_path.exists():
        print(f"Error: ROM file not found at {rom_path}")
        return 1

    print("=" * 70)
    print("M68000 Jump Table Analyzer - Virtua Racing Deluxe")
    print("=" * 70)

    rom_data = read_rom(rom_path)
    print(f"\nROM Size: {len(rom_data):,} bytes\n")

    # Load documented functions
    print("Loading documented functions...")
    documented = load_documented_functions(annotation_file)
    print(f"  Found {len(documented)} documented function addresses\n")

    # Analyze known tables
    print("Analyzing known jump tables...\n")
    table_results = analyze_known_tables(rom_data)

    # Scan for additional potential tables in Priority 8 region
    print("\n" + "=" * 70)
    print("SCANNING FOR JUMP TABLES - PRIORITY 8")
    print("=" * 70)
    print("\nSearching Priority 8 region ($4000-$FFFF) for jump table patterns...")
    potential_tables = find_potential_tables(rom_data, start=0x4000, end=0x10000,
                                             min_entries=8, region_name="Priority 8")
    print(f"Found {len(potential_tables)} potential jump tables in Priority 8\n")

    # Scan Priority 9 regions
    print("\n" + "=" * 70)
    print("SCANNING FOR JUMP TABLES - PRIORITY 9")
    print("=" * 70)

    p9_tables = {}
    for region in PRIORITY_9_REGIONS:
        print(f"\nSearching {region['name']} (${region['start']:05X}-${region['end']:05X})...")
        region_tables = find_potential_tables(
            rom_data,
            start=region['start'],
            end=region['end'],
            min_entries=region['min_entries'],
            region_name=region['name']
        )
        print(f"  Found {len(region_tables)} potential tables")
        p9_tables.update(region_tables)

    print(f"\nTotal Priority 9 tables found: {len(p9_tables)}")

    # Merge all tables
    potential_tables.update(p9_tables)

    # Show top tables by unique handler count
    sorted_tables = sorted(potential_tables.items(),
                          key=lambda x: x[1]['unique_handlers'],
                          reverse=True)[:20]  # Top 20

    print("\n" + "=" * 70)
    print("TOP TABLES BY UNIQUE HANDLER COUNT")
    print("=" * 70)
    for table_id, table_data in sorted_tables:
        region = table_data.get('region', 'Unknown')
        print(f"  ${table_data['offset']:06X} (CPU ${table_data['cpu_addr']:08X}): "
              f"{len(table_data['entries'])} entries, {table_data['unique_handlers']} unique [{region}]")

    # Merge results
    for table_id, table_data in potential_tables.items():
        if table_id not in table_results:
            table_results[table_id] = {
                'location': table_data['offset'],
                'entries': [{'cpu_address': addr} for _, addr, _ in table_data['entries']],
                'handler_addresses': set(addr for _, addr, _ in table_data['entries']),
            }

    # Cross-reference and find new handlers
    print("\n" + "=" * 70)
    print("UNDOCUMENTED HANDLER ADDRESSES")
    print("=" * 70)

    all_handlers = set()
    for table_name, table_data in table_results.items():
        all_handlers.update(table_data['handler_addresses'])

    undocumented = all_handlers - documented

    if undocumented:
        print(f"\nFound {len(undocumented)} potential new functions:\n")
        print(f"{'CPU Address':<12} {'File Offset':<12} {'Function Name':<20}")
        print("-" * 44)

        for addr in sorted(undocumented):
            file_offset = addr - 0x00880000
            func_name = f"func_{file_offset:X}"
            print(f"${addr:08X}       ${file_offset:06X}       {func_name:<20}")
    else:
        print("\nNo new undocumented handlers found in known tables.")

    # Summary
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"Total documented functions: {len(documented)}")
    print(f"Total handlers in tables: {len(all_handlers)}")
    print(f"New handlers found: {len(undocumented)}")

    return 0

if __name__ == '__main__':
    sys.exit(main())
