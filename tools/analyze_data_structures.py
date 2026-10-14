#!/usr/bin/env python3
"""
Analyze SH2 disassembly to identify data structures and memory access patterns
"""

import re
import sys
from collections import defaultdict, Counter

def parse_memory_accesses(filename):
    """Parse disassembly and extract all memory access patterns"""
    accesses = []  # (addr, instruction, offset, register)

    with open(filename, 'r') as f:
        for line in f:
            # Match address and instruction
            match = re.match(r'([0-9A-F]{8})\s+[0-9A-F]+\s+(.+)', line)
            if not match:
                continue

            addr = int(match.group(1), 16)
            instruction = match.group(2).strip()

            # Match displacement loads/stores: MOV.L @($XX,RN),RM
            disp_match = re.search(r'MOV\.\w+\s+(?:@\(\$([0-9A-F]+),R(\d+)\)|R\d+,@\(\$([0-9A-F]+),R(\d+)\))', instruction)
            if disp_match:
                if disp_match.group(1):  # Load
                    offset = int(disp_match.group(1), 16)
                    base_reg = int(disp_match.group(2))
                    accesses.append((addr, 'LOAD', offset, base_reg, instruction))
                else:  # Store
                    offset = int(disp_match.group(3), 16)
                    base_reg = int(disp_match.group(4))
                    accesses.append((addr, 'STORE', offset, base_reg, instruction))

    return accesses

def find_structures(accesses):
    """Identify likely structure definitions from access patterns"""
    # Group by base register
    by_register = defaultdict(list)
    for addr, access_type, offset, base_reg, instr in accesses:
        by_register[base_reg].append((addr, access_type, offset, instr))

    # Analyze patterns
    structures = {}
    for reg, access_list in by_register.items():
        offsets = [offset for _, _, offset, _ in access_list]
        if len(offsets) < 3:  # Need at least 3 accesses to infer structure
            continue

        unique_offsets = sorted(set(offsets))
        if len(unique_offsets) < 2:
            continue

        # Calculate stride (distance between offsets)
        strides = [unique_offsets[i+1] - unique_offsets[i] for i in range(len(unique_offsets)-1)]

        # If we see regular patterns, it's likely a structure
        if len(set(strides)) <= 3:  # Consistent stride pattern
            structures[reg] = {
                'offsets': unique_offsets,
                'max_offset': max(unique_offsets),
                'accesses': len(access_list),
                'sample': access_list[:5]
            }

    return structures

def analyze_loop_structures(filename):
    """Analyze loops that process data structures"""
    loops = []

    with open(filename, 'r') as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        # Find DT (Decrement and Test) instructions - loop counters
        if 'DT' in line and 'R' in line:
            match = re.match(r'([0-9A-F]{8})\s+[0-9A-F]+\s+DT\s+R(\d+)', line)
            if match:
                addr = int(match.group(1), 16)
                counter_reg = int(match.group(2))

                # Look for the BF/S or BF instruction (branch if false)
                if i + 1 < len(lines) and ('BF/S' in lines[i+1] or 'BF' in lines[i+1]):
                    target_match = re.search(r'\$([0-9A-F]+)', lines[i+1])
                    if target_match:
                        target = int(target_match.group(1), 16)
                        loop_size = addr - target

                        # Look for ADD instructions that might indicate stride
                        stride = None
                        for j in range(max(0, i-10), i):
                            add_match = re.search(r'ADD\s+#\$([0-9A-F]+),R(\d+)', lines[j])
                            if add_match:
                                stride = int(add_match.group(1), 16)
                                stride_reg = int(add_match.group(2))
                                break

                        loops.append({
                            'addr': addr,
                            'target': target,
                            'loop_size': loop_size,
                            'counter_reg': counter_reg,
                            'stride': stride
                        })

    return loops

def find_sdram_accesses(filename):
    """Find accesses to SDRAM region (0x22000000)"""
    sdram_accesses = []

    with open(filename, 'r') as f:
        for line in f:
            # Look for immediate loads of SDRAM addresses
            if '2200' in line or '22FF' in line:
                match = re.match(r'([0-9A-F]{8})\s+[0-9A-F]+\s+(.+)', line)
                if match:
                    addr = int(match.group(1), 16)
                    instruction = match.group(2).strip()

                    # Check if it's loading an address
                    if 'MOV.L' in instruction and '@' in instruction and 'PC' in instruction:
                        sdram_accesses.append((addr, instruction))

    return sdram_accesses

def find_mac_operations(filename):
    """Find MAC (Multiply-Accumulate) operations - likely matrix math"""
    mac_sequences = []

    with open(filename, 'r') as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        if 'MAC.L' in line:
            # Found MAC operation - collect surrounding context
            context_start = max(0, i - 5)
            context_end = min(len(lines), i + 10)

            match = re.match(r'([0-9A-F]{8})\s+', line)
            if match:
                addr = int(match.group(1), 16)
                context = lines[context_start:context_end]

                # Count consecutive MAC operations
                mac_count = 1
                for j in range(i+1, context_end):
                    if 'MAC.L' in lines[j]:
                        mac_count += 1
                    else:
                        break

                mac_sequences.append({
                    'addr': addr,
                    'count': mac_count,
                    'context': context
                })

    return mac_sequences

def main():
    if len(sys.argv) < 2:
        print("Usage: analyze_data_structures.py <disassembly_file>")
        sys.exit(1)

    filename = sys.argv[1]

    print("=== DATA STRUCTURE ANALYSIS ===\n")

    # Analyze memory accesses
    print("Parsing memory access patterns...")
    accesses = parse_memory_accesses(filename)
    print(f"Found {len(accesses)} memory accesses with displacement\n")

    # Find structure patterns
    print("=== IDENTIFIED STRUCTURES ===")
    structures = find_structures(accesses)
    for reg, info in sorted(structures.items()):
        print(f"\nStructure accessed via R{reg}:")
        print(f"  Field offsets: {[f'0x{o:02X}' for o in info['offsets']]}")
        print(f"  Max offset: 0x{info['max_offset']:02X} ({info['max_offset']} bytes)")
        print(f"  Estimated size: 0x{info['max_offset'] + 4:02X} bytes")
        print(f"  Access count: {info['accesses']}")
        print(f"  Sample accesses:")
        for addr, atype, offset, instr in info['sample']:
            print(f"    0x{addr:08X}: {instr}")

    # Analyze loops
    print("\n\n=== LOOP ANALYSIS ===")
    loops = analyze_loop_structures(filename)
    print(f"Found {len(loops)} loops with DT counter\n")
    for i, loop in enumerate(loops[:10]):  # Show first 10
        print(f"Loop {i+1} at 0x{loop['addr']:08X}:")
        print(f"  Target: 0x{loop['target']:08X}")
        print(f"  Loop body size: {loop['loop_size']} bytes")
        print(f"  Counter register: R{loop['counter_reg']}")
        if loop['stride']:
            print(f"  Stride: 0x{loop['stride']:02X} bytes")
        print()

    # Find SDRAM usage
    print("\n=== SDRAM ACCESS PATTERNS ===")
    sdram = find_sdram_accesses(filename)
    print(f"Found {len(sdram)} SDRAM address loads\n")
    for addr, instr in sdram[:10]:
        print(f"  0x{addr:08X}: {instr}")

    # Find matrix operations
    print("\n\n=== MATRIX OPERATIONS (MAC.L) ===")
    mac_seqs = find_mac_operations(filename)
    print(f"Found {len(mac_seqs)} MAC operation sequences\n")

    for i, seq in enumerate(mac_seqs[:5]):  # Show first 5
        print(f"MAC sequence {i+1} at 0x{seq['addr']:08X} ({seq['count']} consecutive MACs):")
        for line in seq['context']:
            print(f"  {line}", end='')
        print()

    # Export detailed analysis
    output_file = filename.replace('.asm', '_structures.txt')
    with open(output_file, 'w') as f:
        f.write("=== COMPLETE DATA STRUCTURE ANALYSIS ===\n\n")

        f.write("=== STRUCTURES BY REGISTER ===\n\n")
        for reg, info in sorted(structures.items()):
            f.write(f"R{reg} Structure:\n")
            f.write(f"  Size: ~0x{info['max_offset'] + 4:02X} bytes\n")
            f.write(f"  Fields at offsets: {[f'0x{o:02X}' for o in info['offsets']]}\n")
            f.write(f"  All accesses:\n")
            for addr, atype, offset, instr in sorted(set(info['sample']), key=lambda x: x[2]):
                f.write(f"    +0x{offset:02X}: {instr}\n")
            f.write("\n")

        f.write("\n=== ALL LOOPS ===\n\n")
        for loop in loops:
            f.write(f"Loop at 0x{loop['addr']:08X}:\n")
            f.write(f"  Body size: {loop['loop_size']} bytes\n")
            f.write(f"  Counter: R{loop['counter_reg']}\n")
            if loop['stride']:
                f.write(f"  Stride: 0x{loop['stride']:02X} bytes\n")
            f.write("\n")

    print(f"\nDetailed analysis exported to: {output_file}")

if __name__ == '__main__':
    main()
