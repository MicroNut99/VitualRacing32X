#!/usr/bin/env python3
"""
Annotate 68K module files with properly decoded mnemonics using ROM data.

Unlike annotate_68k_module.py, this tool uses the actual ROM file to properly
decode multi-word instructions. It also identifies function boundaries.

Usage:
    python3 annotate_68k_from_rom.py <module_file> <rom_file> [--output <output_file>]
"""

import re
import sys
import argparse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from m68k_disasm import M68KDisassembler


class M68KFunctionAnalyzer:
    """Analyze 68K code to identify function boundaries."""

    FUNCTION_END_OPCODES = {
        0x4E75,  # RTS
        0x4E73,  # RTE
    }

    # Unconditional jump/branch that ends a block
    BLOCK_END_PATTERNS = [
        (0xFFFF, 0x4EF9),  # JMP xxxx.L
        (0xFFF8, 0x4ED0),  # JMP (An)
        (0xFF00, 0x6000),  # BRA
    ]

    def __init__(self, rom_data, start_offset, end_offset, base_address=0):
        self.rom = rom_data
        self.start = start_offset
        self.end = end_offset
        self.base_addr = base_address

    def read_word(self, offset):
        """Read 16-bit big-endian word."""
        if offset + 2 > len(self.rom):
            return 0
        return (self.rom[offset] << 8) | self.rom[offset + 1]

    def find_functions(self):
        """Find function boundaries based on RTS/RTE instructions."""
        functions = []
        offset = self.start
        func_start = self.start

        while offset < self.end - 1:
            opcode = self.read_word(offset)

            # Check for function end
            if opcode in self.FUNCTION_END_OPCODES:
                # Function ends at RTS/RTE
                func_end = offset
                functions.append({
                    'start_offset': func_start,
                    'end_offset': func_end,
                    'start_addr': self.base_addr + func_start,
                    'end_addr': self.base_addr + func_end,
                    'size': func_end - func_start + 2,
                })
                # Next function starts after this one
                func_start = offset + 2
                # Skip NOP after RTS if present
                if offset + 2 < self.end:
                    next_op = self.read_word(offset + 2)
                    if next_op == 0x4E71:  # NOP
                        func_start = offset + 4

            offset += 2

        return functions


class M68KModuleAnnotator:
    """Annotate 68K module files with properly decoded instructions."""

    def __init__(self, rom_data):
        self.rom = rom_data

    def annotate_file(self, input_path, output_path=None):
        """Annotate a module file with correct 68K mnemonics."""
        with open(input_path, 'r') as f:
            lines = f.readlines()

        # Parse org directive to get base address
        org_address = None
        for line in lines:
            match = re.match(r'\s*org\s+\$([0-9A-Fa-f]+)', line)
            if match:
                org_address = int(match.group(1), 16)
                break

        if org_address is None:
            print(f"Error: Could not find org directive in {input_path}")
            return

        # Find the ROM offset for this module
        # Assume file offset = address for Virtua Racing ROM layout
        rom_offset = org_address

        # Find end address from last DC.W line - look for address comment pattern "; $XXXXXX"
        end_offset = rom_offset
        for line in lines:
            # Match the address comment at the end: "; $006200" or "; $006200 existing mnemonic"
            match = re.search(r';\s*\$([0-9A-Fa-f]{5,6})\s', line)
            if match:
                addr = int(match.group(1), 16)
                if addr > end_offset:
                    end_offset = addr
        end_offset += 16  # Add padding for last instruction

        # Analyze functions
        # For VR ROM: file offset = CPU address, so base_address = 0
        analyzer = M68KFunctionAnalyzer(self.rom, rom_offset, end_offset, base_address=0)
        functions = analyzer.find_functions()

        # Create address-to-function mapping
        func_starts = {f['start_addr']: i + 1 for i, f in enumerate(functions)}

        print(f"Module: {input_path}")
        print(f"Address range: ${org_address:06X} - ${end_offset:06X}")
        print(f"Found {len(functions)} functions")

        # Create disassembler with full ROM
        disasm = M68KDisassembler(self.rom, rom_offset, org_address)

        output_lines = []

        for line in lines:
            # Check for DC.W lines that need annotation
            # Pattern: "    DC.W    $1234,$5678,...  ; $006200 optional old comment"
            dcw_match = re.match(r'(\s+DC\.W\s+)([^;]+)(;\s*\$([0-9A-Fa-f]{5,6}))\s*.*$', line)
            if dcw_match and org_address is not None:
                indent = dcw_match.group(1)
                data = dcw_match.group(2).strip()
                addr_comment = dcw_match.group(3)
                line_addr = int(dcw_match.group(4), 16)

                # Check if this is a function start
                if line_addr in func_starts:
                    func_num = func_starts[line_addr]
                    output_lines.append(f"\n; --- Function #{func_num:02d} @ ${line_addr:06X} ---\n")

                # Parse hex values from DC.W data
                hex_values = re.findall(r'\$([0-9A-Fa-f]+)', data)
                words = [int(h, 16) for h in hex_values]
                line_bytes = len(words) * 2

                # Compute ROM offset for this line
                line_offset = line_addr  # For VR, file offset = address

                # Disassemble from ROM, but ONLY within this line's bytes
                mnemonics = []
                bytes_consumed = 0
                current_addr = line_addr

                while bytes_consumed < line_bytes:
                    if line_offset + bytes_consumed >= len(self.rom) - 1:
                        break

                    try:
                        disasm.offset = line_offset + bytes_consumed
                        opcode = disasm.read_word(disasm.offset)
                        instruction, size = disasm.decode_opcode(opcode, current_addr)

                        # Don't consume more bytes than are on this line
                        if bytes_consumed + size > line_bytes:
                            # Instruction spans to next line - just show opcode
                            mnemonics.append(f"${opcode:04X}...")
                            bytes_consumed += 2
                            current_addr += 2
                        else:
                            mnemonics.append(instruction)
                            bytes_consumed += size
                            current_addr += size
                    except Exception as e:
                        # Fallback for unknown instructions
                        opcode = disasm.read_word(line_offset + bytes_consumed)
                        mnemonics.append(f"DC.W ${opcode:04X}")
                        bytes_consumed += 2
                        current_addr += 2

                # Build annotated line
                mnemonic_str = " ; ".join(mnemonics)
                output_lines.append(f"{indent}{data.rstrip()}{addr_comment} {mnemonic_str}\n")
            else:
                # Pass through non-DC.W lines unchanged
                output_lines.append(line)

        # Write output
        out_path = output_path or input_path
        with open(out_path, 'w') as f:
            f.writelines(output_lines)

        print(f"Annotated: {out_path}")
        return len(functions)


def main():
    parser = argparse.ArgumentParser(
        description='Annotate 68K module files with proper mnemonics from ROM'
    )
    parser.add_argument('module_file', type=Path, help='Input module file')
    parser.add_argument('rom_file', type=Path, help='ROM file for disassembly')
    parser.add_argument('--output', '-o', type=Path, help='Output file (default: overwrite input)')

    args = parser.parse_args()

    if not args.module_file.exists():
        print(f"Error: Module file {args.module_file} not found")
        sys.exit(1)

    if not args.rom_file.exists():
        print(f"Error: ROM file {args.rom_file} not found")
        sys.exit(1)

    # Load ROM
    with open(args.rom_file, 'rb') as f:
        rom_data = f.read()

    annotator = M68KModuleAnnotator(rom_data)
    annotator.annotate_file(args.module_file, args.output)


if __name__ == '__main__':
    main()
