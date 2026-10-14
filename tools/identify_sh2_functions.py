#!/usr/bin/env python3
"""
Identify SH2 function boundaries in annotated module files.

Analyzes SH2 code to find function prologues, epilogues, and boundaries.

Usage:
    python3 identify_sh2_functions.py <rom_file> <start_offset> <end_offset>
"""

import sys
import struct
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from sh2_disasm import SH2Disassembler


class SH2FunctionAnalyzer:
    """Analyze SH2 code to identify function boundaries."""

    def __init__(self, rom_data, start_offset, end_offset, base_address=None):
        self.rom = rom_data
        self.start = start_offset
        self.end = end_offset
        # SH2 code is loaded to SDRAM at 0x02000000 + ROM offset
        if base_address is None:
            base_address = 0x02000000
        self.base_addr = base_address
        self.disasm = SH2Disassembler(rom_data, start_offset, base_address + start_offset)

        self.functions = []
        self.current_function = None

    def read_word(self, offset):
        """Read 16-bit big-endian word."""
        return struct.unpack('>H', self.rom[offset:offset+2])[0]

    def analyze(self):
        """Analyze the code section to identify functions."""
        offset = self.start
        potential_starts = []
        returns = []

        print(f"Analyzing SH2 code from ${offset:06X} to ${self.end:06X}")
        print("=" * 80)

        # First pass: identify key instructions
        while offset < self.end:
            opcode = self.read_word(offset)
            addr = self.base_addr + offset

            # RTS - function return
            if opcode == 0x000B:
                returns.append((offset, addr))

            # RTE - interrupt return
            elif opcode == 0x002B:
                returns.append((offset, addr))

            # STS.L PR,@-R15 - function prologue (save return address)
            elif opcode == 0x4F22:
                potential_starts.append((offset, addr, 'PROLOGUE'))

            # BSR - branch to subroutine
            elif (opcode & 0xF000) == 0xB000:
                disp = opcode & 0xFFF
                if disp & 0x800:
                    disp = disp - 0x1000
                target_addr = addr + 4 + (disp * 2)
                target_offset = target_addr - self.base_addr
                if self.start <= target_offset < self.end:
                    potential_starts.append((target_offset, target_addr, 'BSR_TARGET'))

            # JSR @Rn - jump to subroutine (less useful for static analysis)
            elif (opcode & 0xF0FF) == 0x400B:
                pass  # Dynamic call

            offset += 2

        # Second pass: match returns to function starts
        print(f"\nFound {len(returns)} RTS/RTE instructions")
        print(f"Found {len(potential_starts)} potential function starts\n")

        # Find function boundaries
        functions = []

        # Start from known entry point
        if self.start in [s[0] for s in potential_starts]:
            func_start = self.start
        else:
            func_start = self.start

        for i, (ret_offset, ret_addr) in enumerate(returns):
            # Check for NOP after RTS (delay slot)
            if ret_offset + 2 < self.end:
                next_opcode = self.read_word(ret_offset + 2)
                func_end = ret_offset + 2  # Include delay slot

                # Next function likely starts after the delay slot
                next_start = ret_offset + 4

                # Skip padding/data
                while next_start < self.end:
                    word = self.read_word(next_start)
                    # Check if it looks like code (not obvious data)
                    if word != 0x0000 and word != 0xFFFF:
                        break
                    next_start += 2

                func_addr_start = self.base_addr + func_start
                func_addr_end = self.base_addr + func_end

                functions.append({
                    'start_offset': func_start,
                    'end_offset': func_end,
                    'start_addr': func_addr_start,
                    'end_addr': func_addr_end,
                    'size': func_end - func_start + 2,
                })

                func_start = next_start

        self.functions = functions
        return functions

    def print_functions(self):
        """Print identified functions."""
        print("Identified Functions:")
        print("=" * 80)
        print(f"{'#':<4} {'Start Addr':<12} {'End Addr':<12} {'Size':<8} {'Offset Range'}")
        print("-" * 80)

        for i, func in enumerate(self.functions):
            print(f"{i+1:<4} ${func['start_addr']:08X}   ${func['end_addr']:08X}   "
                  f"{func['size']:<8} ${func['start_offset']:06X}-${func['end_offset']:06X}")

        print(f"\nTotal functions: {len(self.functions)}")

    def disassemble_function(self, func_index):
        """Disassemble a specific function."""
        if func_index >= len(self.functions):
            print(f"Function {func_index} not found")
            return

        func = self.functions[func_index]
        print(f"\nFunction {func_index + 1}: ${func['start_addr']:08X} - ${func['end_addr']:08X}")
        print("=" * 80)

        disasm = SH2Disassembler(
            self.rom,
            func['start_offset'],
            func['start_addr']
        )

        instructions = disasm.disassemble_range(
            func['start_offset'],
            func['end_offset'] + 2,
        )

        for instr in instructions:
            print(instr)


def main():
    if len(sys.argv) < 4:
        print("Usage: identify_sh2_functions.py <rom_file> <start_offset> <end_offset>")
        print("\nExample:")
        print("  python3 identify_sh2_functions.py vr.32x 0x024200 0x0261FF")
        sys.exit(1)

    rom_file = sys.argv[1]
    start_offset = int(sys.argv[2], 16)
    end_offset = int(sys.argv[3], 16)

    with open(rom_file, 'rb') as f:
        rom_data = f.read()

    analyzer = SH2FunctionAnalyzer(rom_data, start_offset, end_offset)
    analyzer.analyze()
    analyzer.print_functions()

    # Optionally disassemble first few functions
    print("\n" + "=" * 80)
    print("First 5 functions (disassembled):")
    print("=" * 80)

    for i in range(min(5, len(analyzer.functions))):
        analyzer.disassemble_function(i)
        print()


if __name__ == '__main__':
    main()
