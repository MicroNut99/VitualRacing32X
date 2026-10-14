#!/usr/bin/env python3
"""
Create comprehensive function inventory from ROM

Scans ROM for all functions, creates initial catalog with:
- Address, size, type
- Call frequency estimates
- Complexity metrics
- Cross-references
"""

import sys
import struct
from pathlib import Path
from collections import defaultdict

def find_functions(rom_data, start=0x200, end=None):
    """
    Scan ROM for function-like patterns

    Heuristics:
    - BSR targets (definite functions)
    - JSR targets (definite functions)
    - RTS endings (function boundaries)
    - Prologue patterns (stack frame setup)
    """
    if end is None:
        end = len(rom_data)

    functions = {}
    bsr_targets = set()
    jsr_targets = set()

    # First pass: Find all BSR/JSR call targets
    print("Pass 1: Finding BSR/JSR targets...")
    for addr in range(start, end - 1, 2):
        opcode = struct.unpack('>H', rom_data[addr:addr+2])[0]

        # BSR (Branch to Subroutine): 1011 dddd dddd dddd
        if (opcode & 0xF000) == 0xB000:
            # Displacement is signed 12-bit
            disp = opcode & 0x0FFF
            if disp & 0x0800:  # Sign extend
                disp |= 0xFFFFF000
            # Target = PC + 4 + (disp * 2)
            target = addr + 4 + (disp * 2)
            if start <= target < end:
                bsr_targets.add(target)

        # JSR @Rm: 0100 mmmm 0000 1011
        # JSR @(disp,PC): 1011 dddd dddd dddd (wait, that's BSR)
        # Actually JSR uses: 0100 mmmm 0000 1011 (register indirect)
        # We need to track JSR differently - skip for now

    print(f"  Found {len(bsr_targets)} BSR targets")

    # Second pass: Find RTS instructions (function ends)
    print("Pass 2: Finding RTS boundaries...")
    rts_addresses = []
    for addr in range(start, end - 1, 2):
        opcode = struct.unpack('>H', rom_data[addr:addr+2])[0]
        if opcode == 0x000B:  # RTS
            rts_addresses.append(addr)

    print(f"  Found {len(rts_addresses)} RTS instructions")

    # Third pass: Match BSR targets with next RTS to define functions
    print("Pass 3: Defining function boundaries...")
    for target in sorted(bsr_targets):
        # Find next RTS after this target
        func_end = None
        for rts_addr in rts_addresses:
            if rts_addr > target:
                func_end = rts_addr + 2  # Include RTS + delay slot
                break

        if func_end and func_end - target < 2000:  # Sanity check: < 2KB
            functions[target] = {
                'start': target,
                'end': func_end,
                'size': func_end - target,
                'type': 'bsr_target',
                'callers': [],
                'calls': [],
            }

    print(f"  Defined {len(functions)} functions")

    return functions

def analyze_function(rom_data, func):
    """Analyze function for complexity, register usage, etc."""
    start = func['start']
    end = func['end']
    size = func['size']

    # Count instructions
    instr_count = size // 2

    # Find branches (complexity indicator)
    branches = 0
    loops = 0

    for addr in range(start, end, 2):
        if addr + 2 > len(rom_data):
            break
        opcode = struct.unpack('>H', rom_data[addr:addr+2])[0]

        # Branch instructions: BF, BT, BRA, BSR, etc.
        if (opcode & 0xF000) in [0x8000, 0x9000, 0xA000, 0xB000]:
            branches += 1
            # Check if it's a backward branch (loop)
            disp = opcode & 0x0FFF
            if disp & 0x0800:  # Negative displacement
                loops += 1

    # Estimate complexity
    complexity = 'simple'
    if branches > 5 or loops > 2:
        complexity = 'medium'
    if branches > 10 or loops > 4 or size > 500:
        complexity = 'complex'

    func['instructions'] = instr_count
    func['branches'] = branches
    func['loops'] = loops
    func['complexity'] = complexity

    return func

def find_callers(rom_data, functions):
    """Find who calls each function"""
    print("\nFinding callers...")

    for addr in range(0x200, len(rom_data) - 1, 2):
        opcode = struct.unpack('>H', rom_data[addr:addr+2])[0]

        # BSR
        if (opcode & 0xF000) == 0xB000:
            disp = opcode & 0x0FFF
            if disp & 0x0800:
                disp |= 0xFFFFF000
            target = addr + 4 + (disp * 2)

            if target in functions:
                functions[target]['callers'].append(addr)

    # Count call frequency
    for func in functions.values():
        func['call_count'] = len(func['callers'])

def main():
    print("=" * 70)
    print(" Virtua Racing 32X - Function Inventory Generator")
    print("=" * 70)

    rom_file = Path("Virtua Racing Deluxe (USA).32x")
    if not rom_file.exists():
        print(f"\n❌ ROM not found: {rom_file}")
        sys.exit(1)

    print(f"\n✓ Reading ROM: {rom_file}")
    rom_data = rom_file.read_bytes()
    print(f"  Size: {len(rom_data):,} bytes")

    # Focus on SH2 code region (rough estimate: 0x000200 - 0x100000)
    print("\n" + "=" * 70)
    print("Scanning for functions...")
    print("=" * 70)

    functions = find_functions(rom_data, start=0x200, end=0x100000)

    # Analyze each function
    print("\n" + "=" * 70)
    print("Analyzing functions...")
    print("=" * 70)

    for addr, func in functions.items():
        analyze_function(rom_data, func)

    # Find callers
    find_callers(rom_data, functions)

    # Generate report
    print("\n" + "=" * 70)
    print("FUNCTION INVENTORY")
    print("=" * 70)

    output_file = Path("analysis/FUNCTION_INVENTORY.md")
    output_file.parent.mkdir(exist_ok=True)

    with output_file.open('w') as f:
        f.write("# Virtua Racing 32X - Function Inventory\n\n")
        f.write(f"**Total functions found:** {len(functions)}\n\n")

        f.write("## Summary by Complexity\n\n")
        complexity_counts = defaultdict(int)
        for func in functions.values():
            complexity_counts[func['complexity']] += 1

        for comp in ['simple', 'medium', 'complex']:
            count = complexity_counts[comp]
            pct = count / len(functions) * 100
            f.write(f"- **{comp.title()}:** {count} ({pct:.1f}%)\n")

        f.write("\n## Summary by Size\n\n")
        sizes = [f['size'] for f in functions.values()]
        f.write(f"- **Total code:** {sum(sizes):,} bytes\n")
        f.write(f"- **Average function:** {sum(sizes) // len(sizes)} bytes\n")
        f.write(f"- **Largest:** {max(sizes)} bytes\n")
        f.write(f"- **Smallest:** {min(sizes)} bytes\n")

        f.write("\n## Hot Functions (Most Called)\n\n")
        f.write("| Address | Size | Calls | Complexity | Instructions |\n")
        f.write("|---------|------|-------|------------|-------------|\n")

        # Sort by call count
        sorted_funcs = sorted(functions.items(),
                            key=lambda x: x[1]['call_count'],
                            reverse=True)

        for addr, func in sorted_funcs[:30]:  # Top 30
            f.write(f"| 0x{addr:06X} | {func['size']:3d}B | "
                   f"{func['call_count']:3d}× | {func['complexity']:7s} | "
                   f"{func['instructions']:3d} |\n")

        f.write("\n## All Functions\n\n")
        f.write("| Address | Size | Type | Complexity | Branches | Loops | Calls |\n")
        f.write("|---------|------|------|------------|----------|-------|-------|\n")

        for addr in sorted(functions.keys()):
            func = functions[addr]
            f.write(f"| 0x{addr:06X} | {func['size']:3d}B | "
                   f"{func['type']:10s} | {func['complexity']:7s} | "
                   f"{func['branches']:2d} | {func['loops']:2d} | "
                   f"{func['call_count']:3d}× |\n")

        # Special section: func_065
        if 0x23F2E in functions:
            f.write("\n## func_065 (Our Problem Child)\n\n")
            func = functions[0x23F2E]
            f.write(f"**Address:** 0x{0x23F2E:06X}\n")
            f.write(f"**Size:** {func['size']} bytes\n")
            f.write(f"**Complexity:** {func['complexity']}\n")
            f.write(f"**Called by:** {func['call_count']} callers\n")
            f.write(f"**Branches:** {func['branches']}\n")
            f.write(f"**Loops:** {func['loops']}\n\n")

            f.write("**Callers:**\n")
            for caller in func['callers'][:10]:  # First 10
                f.write(f"- 0x{caller:06X}\n")
            if len(func['callers']) > 10:
                f.write(f"- ... and {len(func['callers']) - 10} more\n")

    print(f"\n✓ Saved inventory: {output_file}")
    print(f"\nTop 10 most-called functions:")
    for addr, func in sorted_funcs[:10]:
        print(f"  0x{addr:06X}: {func['call_count']:3d} calls, "
              f"{func['size']:3d} bytes, {func['complexity']}")

    # Check func_065
    if 0x23F2E in functions:
        func = functions[0x23F2E]
        print(f"\n✓ func_065 found:")
        print(f"  Address: 0x23F2E")
        print(f"  Size: {func['size']} bytes")
        print(f"  Called: {func['call_count']} times")
        print(f"  Complexity: {func['complexity']}")

if __name__ == '__main__':
    main()
