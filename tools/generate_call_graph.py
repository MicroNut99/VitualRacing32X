#!/usr/bin/env python3
"""
Generate call graph from ROM

Outputs:
1. DOT file (Graphviz) for visualization
2. Text report with call chains
3. Hot path analysis
"""

import sys
import struct
from pathlib import Path
from collections import defaultdict, deque

def find_all_bsr_calls(rom_data, start=0x200, end=0x100000):
    """Find all BSR call sites and their targets"""
    calls = []  # List of (caller_addr, target_addr)

    for addr in range(start, min(end, len(rom_data) - 1), 2):
        opcode = struct.unpack('>H', rom_data[addr:addr+2])[0]

        # BSR (Branch to Subroutine): 1011 dddd dddd dddd
        if (opcode & 0xF000) == 0xB000:
            disp = opcode & 0xFFF
            if disp & 0x800:  # Sign extend
                disp = (disp | 0xFFFFF000) - 0x100000000
            target = addr + 4 + (disp * 2)

            if start <= target < end:
                calls.append((addr, target))

    return calls

def build_call_graph(calls):
    """Build directed graph from call list"""
    graph = defaultdict(set)  # caller → set of callees
    reverse_graph = defaultdict(set)  # callee → set of callers

    for caller, callee in calls:
        graph[caller].add(callee)
        reverse_graph[callee].add(caller)

    return graph, reverse_graph

def find_functions(reverse_graph, calls):
    """Identify unique functions (BSR targets)"""
    functions = set()

    # All BSR targets are functions
    for caller, target in calls:
        functions.add(target)

    return sorted(functions)

def analyze_hot_paths(graph, reverse_graph, functions):
    """Find most-called functions and deepest call chains"""
    # Count calls to each function
    call_counts = {func: len(reverse_graph.get(func, set())) for func in functions}

    # Sort by call count
    hot_functions = sorted(call_counts.items(), key=lambda x: x[1], reverse=True)

    return hot_functions

def find_call_chains(graph, start_func, max_depth=5):
    """Find call chains starting from a function (BFS)"""
    chains = []
    queue = deque([(start_func, [start_func])])
    visited = set()

    while queue:
        func, path = queue.popleft()

        if len(path) > max_depth:
            continue

        if func in visited:
            continue
        visited.add(func)

        # Get callees
        callees = graph.get(func, set())

        if not callees:
            # Leaf function
            chains.append(path)
        else:
            for callee in callees:
                new_path = path + [callee]
                queue.append((callee, new_path))

    return chains

def generate_dot(graph, functions, hot_functions, output_file):
    """Generate Graphviz DOT file"""
    with open(output_file, 'w') as f:
        f.write("digraph CallGraph {\n")
        f.write("  rankdir=LR;\n")
        f.write("  node [shape=box];\n\n")

        # Color hot functions
        top_10 = set(addr for addr, _ in hot_functions[:10])

        # Nodes
        for func in functions:
            label = f"0x{func:06X}"

            if func in top_10:
                call_count = next(count for addr, count in hot_functions if addr == func)
                f.write(f'  "0x{func:06X}" [label="{label}\\n({call_count} calls)", style=filled, fillcolor=orange];\n')
            else:
                f.write(f'  "0x{func:06X}" [label="{label}"];\n')

        f.write("\n  // Edges\n")

        # Edges
        for caller, callees in graph.items():
            for callee in callees:
                f.write(f'  "0x{caller:06X}" -> "0x{callee:06X}";\n')

        f.write("}\n")

def main():
    print("=" * 70)
    print(" Virtua Racing 32X - Call Graph Generator")
    print("=" * 70)

    rom_file = Path("Virtua Racing Deluxe (USA).32x")
    if not rom_file.exists():
        print(f"\n❌ ROM not found: {rom_file}")
        sys.exit(1)

    print(f"\n✓ Reading ROM: {rom_file}")
    rom_data = rom_file.read_bytes()

    # Find all calls
    print("\nScanning for BSR calls...")
    calls = find_all_bsr_calls(rom_data)
    print(f"  Found {len(calls)} BSR calls")

    # Build graph
    print("\nBuilding call graph...")
    graph, reverse_graph = build_call_graph(calls)
    functions = find_functions(reverse_graph, calls)
    print(f"  Functions: {len(functions)}")
    print(f"  Unique callers: {len(graph)}")

    # Analyze hot paths
    print("\nAnalyzing hot functions...")
    hot_functions = analyze_hot_paths(graph, reverse_graph, functions)

    # Generate reports
    output_dir = Path("analysis")
    output_dir.mkdir(exist_ok=True)

    # 1. DOT file
    dot_file = output_dir / "call_graph.dot"
    print(f"\n✓ Generating DOT file: {dot_file}")
    generate_dot(graph, functions, hot_functions, dot_file)
    print(f"  To visualize: dot -Tpng {dot_file} -o call_graph.png")

    # 2. Text report
    report_file = output_dir / "CALL_GRAPH_REPORT.md"
    print(f"\n✓ Generating report: {report_file}")

    with report_file.open('w') as f:
        f.write("# Call Graph Report\n\n")
        f.write(f"**Total functions:** {len(functions)}\n")
        f.write(f"**Total call sites:** {len(calls)}\n")
        f.write(f"**Average calls per function:** {len(calls) / len(functions):.1f}\n\n")

        f.write("## Top 20 Most-Called Functions\n\n")
        f.write("| Rank | Address | Calls | Callers |\n")
        f.write("|------|---------|-------|----------|\n")

        for rank, (addr, count) in enumerate(hot_functions[:20], 1):
            callers = reverse_graph[addr]
            caller_list = ', '.join(f"0x{c:06X}" for c in sorted(callers)[:3])
            if len(callers) > 3:
                caller_list += f", ... +{len(callers)-3}"
            f.write(f"| {rank} | 0x{addr:06X} | {count} | {caller_list} |\n")

        f.write("\n## Call Chains (Top Function)\n\n")
        if hot_functions:
            top_func = hot_functions[0][0]
            f.write(f"Starting from 0x{top_func:06X} (most called):\n\n")

            chains = find_call_chains(graph, top_func, max_depth=3)
            for i, chain in enumerate(chains[:10], 1):
                chain_str = " → ".join(f"0x{addr:06X}" for addr in chain)
                f.write(f"{i}. {chain_str}\n")

            if len(chains) > 10:
                f.write(f"\n... and {len(chains) - 10} more chains\n")

        f.write("\n## Leaf Functions (Never Call Others)\n\n")
        leaves = [func for func in functions if func not in graph or not graph[func]]
        f.write(f"**Count:** {len(leaves)}\n\n")

        for leaf in leaves[:20]:
            call_count = len(reverse_graph.get(leaf, set()))
            f.write(f"- 0x{leaf:06X} ({call_count} calls)\n")

        if len(leaves) > 20:
            f.write(f"- ... and {len(leaves) - 20} more\n")

    print(f"\n✓ Analysis complete!")
    print(f"\nTop 10 hottest functions:")
    for rank, (addr, count) in enumerate(hot_functions[:10], 1):
        print(f"  {rank}. 0x{addr:06X}: {count} calls")

if __name__ == '__main__':
    main()
