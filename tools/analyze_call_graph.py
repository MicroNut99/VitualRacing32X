#!/usr/bin/env python3
"""
Analyze SH2 disassembly to extract function call graph
"""

import re
import sys
from collections import defaultdict

def parse_disassembly(filename):
    """Parse disassembly file and extract functions and calls"""
    functions = []  # List of (start_addr, end_addr)
    calls = []  # List of (from_addr, to_addr, call_type)
    current_func_start = None

    with open(filename, 'r') as f:
        for line in f:
            # Match address and instruction (format: ADDRESS  OPCODE  INSTRUCTION)
            match = re.match(r'([0-9A-F]{8})\s+[0-9A-F]+\s+(.+)', line)
            if not match:
                continue

            addr_str = match.group(1)
            addr = int(addr_str, 16)
            instruction = match.group(2).strip()

            # Check for function start (after RTS or first instruction)
            if 'RTS' in instruction:
                if current_func_start is not None:
                    functions.append((current_func_start, addr))
                current_func_start = None
            elif current_func_start is None and not instruction.startswith('DW'):
                # Potential function start (non-data)
                current_func_start = addr

            # Extract BSR calls (Branch to SubRoutine)
            bsr_match = re.search(r'BSR\s+\$([0-9A-F]+)', instruction)
            if bsr_match:
                target = int(bsr_match.group(1), 16)
                calls.append((addr, target, 'BSR'))

            # Extract JSR calls (Jump to SubRoutine)
            jsr_match = re.search(r'JSR\s+@R(\d+)', instruction)
            if jsr_match:
                # Indirect call through register
                calls.append((addr, None, f'JSR_@R{jsr_match.group(1)}'))

    return functions, calls

def build_call_graph(functions, calls):
    """Build call graph data structure"""
    # Map address to function index
    addr_to_func = {}
    for i, (start, end) in enumerate(functions):
        for addr in range(start, end + 2, 2):  # SH2 instructions are 2 bytes
            addr_to_func[addr] = i

    # Build graph
    graph = defaultdict(set)  # func_idx -> set of called func_idx
    indirect_calls = defaultdict(list)  # func_idx -> list of indirect calls

    for from_addr, to_addr, call_type in calls:
        if from_addr not in addr_to_func:
            continue
        from_func = addr_to_func[from_addr]

        if to_addr is None:
            # Indirect call
            indirect_calls[from_func].append(call_type)
        elif to_addr in addr_to_func:
            to_func = addr_to_func[to_addr]
            graph[from_func].add(to_func)

    return graph, indirect_calls, addr_to_func

def find_entry_points(functions, graph):
    """Find functions that are called but never appear as callers (entry points)"""
    all_funcs = set(range(len(functions)))
    called_funcs = set()
    for callees in graph.values():
        called_funcs.update(callees)

    # Entry points are functions that are never the target of a call
    # OR are at the very beginning
    potential_entries = []
    for i, (start, end) in enumerate(functions):
        if i not in called_funcs or start == functions[0][0]:
            potential_entries.append(i)

    return potential_entries

def find_leaf_functions(functions, graph):
    """Find functions that never call other functions (leaf functions)"""
    all_funcs = set(range(len(functions)))
    calling_funcs = set(graph.keys())
    leaf_funcs = all_funcs - calling_funcs
    return sorted(leaf_funcs)

def categorize_functions(functions, graph, addr_to_func):
    """Categorize functions by likely purpose"""
    init_funcs = []
    loop_funcs = []
    utility_funcs = []

    for i, (start, end) in enumerate(functions):
        call_count = sum(1 for callers in graph.values() if i in callers)

        if call_count == 0:
            # Never called - likely initialization
            init_funcs.append(i)
        elif call_count == 1:
            # Called once - could be init or main loop
            loop_funcs.append(i)
        else:
            # Called multiple times - likely utility
            utility_funcs.append(i)

    return init_funcs, loop_funcs, utility_funcs

def main():
    if len(sys.argv) < 2:
        print("Usage: analyze_call_graph.py <disassembly_file>")
        sys.exit(1)

    filename = sys.argv[1]

    print("Parsing disassembly...")
    functions, calls = parse_disassembly(filename)

    print(f"\n=== FUNCTION STATISTICS ===")
    print(f"Total functions found: {len(functions)}")
    print(f"Total calls found: {len(calls)}")
    print(f"  Direct calls (BSR): {sum(1 for _, _, t in calls if t == 'BSR')}")
    print(f"  Indirect calls (JSR): {sum(1 for _, _, t in calls if 'JSR' in t)}")

    print("\n=== FUNCTION BOUNDARIES ===")
    for i, (start, end) in enumerate(functions[:20]):  # Show first 20
        size = end - start + 2
        print(f"func_{i:03d}: 0x{start:08X} - 0x{end:08X} ({size:4d} bytes)")
    if len(functions) > 20:
        print(f"... and {len(functions) - 20} more functions")

    print("\n=== BUILDING CALL GRAPH ===")
    graph, indirect_calls, addr_to_func = build_call_graph(functions, calls)

    print(f"Functions with outgoing calls: {len(graph)}")
    print(f"Functions with indirect calls: {len(indirect_calls)}")

    # Find entry points
    entry_points = find_entry_points(functions, graph)
    print(f"\n=== ENTRY POINT FUNCTIONS ===")
    print(f"Potential entry points: {len(entry_points)}")
    for i in entry_points[:10]:
        start, end = functions[i]
        print(f"  func_{i:03d}: 0x{start:08X}")

    # Find leaf functions
    leaf_funcs = find_leaf_functions(functions, graph)
    print(f"\n=== LEAF FUNCTIONS ===")
    print(f"Functions that don't call others: {len(leaf_funcs)}")
    for i in leaf_funcs[:10]:
        start, end = functions[i]
        print(f"  func_{i:03d}: 0x{start:08X}")

    # Categorize functions
    init_funcs, loop_funcs, utility_funcs = categorize_functions(functions, graph, addr_to_func)
    print(f"\n=== FUNCTION CATEGORIZATION ===")
    print(f"Likely initialization: {len(init_funcs)}")
    print(f"Likely per-frame/loop: {len(loop_funcs)}")
    print(f"Likely utility: {len(utility_funcs)}")

    # Show call graph for first few functions
    print(f"\n=== CALL GRAPH SAMPLE ===")
    for i in range(min(15, len(functions))):
        if i in graph or i in indirect_calls:
            start, _ = functions[i]
            print(f"func_{i:03d} (0x{start:08X}):")
            if i in graph:
                for j in sorted(graph[i]):
                    target_start, _ = functions[j]
                    print(f"  -> func_{j:03d} (0x{target_start:08X})")
            if i in indirect_calls:
                for call_type in indirect_calls[i]:
                    print(f"  -> {call_type} (indirect)")

    # Show most-called functions (hot functions)
    print(f"\n=== MOST CALLED FUNCTIONS (HOTSPOTS) ===")
    call_counts = defaultdict(int)
    for callees in graph.values():
        for callee in callees:
            call_counts[callee] += 1

    top_funcs = sorted(call_counts.items(), key=lambda x: x[1], reverse=True)[:10]
    for func_idx, count in top_funcs:
        start, end = functions[func_idx]
        print(f"  func_{func_idx:03d} (0x{start:08X}): called {count} times")

    # Export full call graph to file
    output_file = filename.replace('.asm', '_callgraph.txt')
    with open(output_file, 'w') as f:
        f.write("=== COMPLETE CALL GRAPH ===\n\n")
        for i in range(len(functions)):
            start, end = functions[i]
            f.write(f"\nfunc_{i:03d} (0x{start:08X} - 0x{end:08X}):\n")
            if i in graph:
                for j in sorted(graph[i]):
                    target_start, _ = functions[j]
                    f.write(f"  -> func_{j:03d} (0x{target_start:08X})\n")
            if i in indirect_calls:
                for call_type in indirect_calls[i]:
                    f.write(f"  -> {call_type} (indirect)\n")
            if i not in graph and i not in indirect_calls:
                f.write(f"  (leaf function - no calls)\n")

    print(f"\nComplete call graph exported to: {output_file}")

if __name__ == '__main__':
    main()
