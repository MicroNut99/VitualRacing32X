#!/usr/bin/env python3
"""
SH2 Linker for Virtua Racing Deluxe Slave Engine
Handles offset calculations, symbol resolution, and ROM binary injection

Usage:
    python3 sh2_linker.py <input_asm> <output_binary> [--rom rom_file] [--inject offset]
"""

import sys
import struct
import subprocess
import os
import re
from pathlib import Path

class SH2Linker:
    def __init__(self, asm_file, output_bin, rom_file=None, inject_offset=None):
        self.asm_file = asm_file
        self.output_bin = output_bin
        self.rom_file = rom_file
        self.inject_offset = inject_offset or 0x20650

        self.symbols = {}
        self.binary = b''
        self.object_file = output_bin.replace('.bin', '.o')

    def assemble(self):
        """Assemble SH2 code to object file"""
        print(f"[*] Assembling: {self.asm_file}")

        result = subprocess.run(
            ['sh-elf-as', '-o', self.object_file, self.asm_file],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            print(f"[!] Assembly failed: {result.stderr}")
            sys.exit(1)

        print(f"[+] Object file: {self.object_file}")

    def extract_binary(self):
        """Convert object file to binary"""
        print(f"[*] Extracting binary: {self.object_file} -> {self.output_bin}")

        result = subprocess.run(
            ['sh-elf-objcopy', '-O', 'binary', self.object_file, self.output_bin],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            print(f"[!] Binary extraction failed: {result.stderr}")
            sys.exit(1)

        with open(self.output_bin, 'rb') as f:
            self.binary = f.read()

        print(f"[+] Binary size: {len(self.binary)} bytes")

    def extract_symbols(self):
        """Extract symbol table from object file"""
        print(f"[*] Extracting symbols from: {self.object_file}")

        result = subprocess.run(
            ['sh-elf-nm', '-n', self.object_file],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            print(f"[!] Symbol extraction failed: {result.stderr}")
            return

        for line in result.stdout.strip().split('\n'):
            if not line:
                continue

            parts = line.split()
            if len(parts) >= 3:
                addr = parts[0]
                symbol = parts[2]

                # Parse hex address
                try:
                    offset = int(addr, 16)
                    self.symbols[symbol] = offset
                except ValueError:
                    pass

        print(f"[+] Found {len(self.symbols)} symbols")

    def print_memory_map(self):
        """Print memory layout and symbol addresses"""
        print("\n" + "="*70)
        print("SH2 Slave Engine Memory Map (ROM relative)")
        print("="*70)

        rom_base = self.inject_offset

        print(f"\nROM Base Address: 0x{rom_base:06X}")
        print(f"Binary Size:     {len(self.binary):,} bytes")
        print(f"ROM End:         0x{rom_base + len(self.binary):06X}\n")

        print("Symbols:")
        print("-" * 70)

        sorted_symbols = sorted(self.symbols.items(), key=lambda x: x[1])

        for symbol, offset in sorted_symbols:
            rom_addr = rom_base + offset
            stage = self._get_stage_name(symbol)
            print(f"  {symbol:30s}  Offset: 0x{offset:04X}  ROM: 0x{rom_addr:06X}  {stage}")

        print("\n" + "="*70)

    def _get_stage_name(self, symbol):
        """Return phase/stage name for a symbol"""
        phase_map = {
            'slave_main_loop': 'Phase 1: Main loop',
            'slave_process_polygons': 'Phase 1: Polygon processor',
            'parse_polygon_bounds': 'Phase 3.0: Bounds parser',
            'slave_func_029': 'Phase 3.1: Region codes',
            'slave_func_032': 'Phase 3.2: Scanline fill',
            'slave_func_033': 'Phase 3.3: Polygon renderer',
            'slave_func_034': 'Phase 3.3: Bresenham raster',
            'slave_func_023': 'Phase 3.4: Dispatcher',
        }
        return phase_map.get(symbol, '')

    def inject_into_rom(self):
        """Inject binary into ROM at calculated offset"""
        if not self.rom_file:
            print("[!] No ROM file specified, skipping injection")
            return

        if not os.path.exists(self.rom_file):
            print(f"[!] ROM file not found: {self.rom_file}")
            return

        print(f"\n[*] Injecting into ROM: {self.rom_file}")

        with open(self.rom_file, 'r+b') as f:
            # Verify ROM size
            f.seek(0, 2)
            rom_size = f.tell()

            if self.inject_offset + len(self.binary) > rom_size:
                print(f"[!] Binary too large for ROM!")
                print(f"    Binary size:      {len(self.binary)} bytes")
                print(f"    Inject offset:    0x{self.inject_offset:06X}")
                print(f"    End address:      0x{self.inject_offset + len(self.binary):06X}")
                print(f"    ROM size:         {rom_size} bytes")
                return

            # Inject binary
            f.seek(self.inject_offset)
            f.write(self.binary)

            print(f"[+] Injection successful!")
            print(f"    Offset:  0x{self.inject_offset:06X}")
            print(f"    Size:    {len(self.binary)} bytes")
            print(f"    End:     0x{self.inject_offset + len(self.binary):06X}")

    def generate_injection_commands(self):
        """Generate shell commands for ROM injection"""
        print("\n" + "="*70)
        print("ROM Injection Commands (for Makefile)")
        print("="*70 + "\n")

        print(f"dd if={self.output_bin} of=<rom_file> bs=1 seek=$((0x{self.inject_offset:X})) conv=notrunc")

        print("\n" + "="*70)

    def run(self):
        """Execute full linker pipeline"""
        print("\n[*] SH2 Linker Starting...")

        self.assemble()
        self.extract_binary()
        self.extract_symbols()
        self.print_memory_map()
        self.generate_injection_commands()

        if self.rom_file:
            self.inject_into_rom()

        print("\n[+] Linker complete!")


def main():
    if len(sys.argv) < 3:
        print("Usage: sh2_linker.py <input.asm> <output.bin> [--rom romfile] [--inject offset]")
        print("")
        print("Examples:")
        print("  sh2_linker.py disasm/sh2_slave_consolidated.asm build/sh2_slave.bin")
        print("  sh2_linker.py disasm/sh2_slave_consolidated.asm build/sh2_slave.bin --rom build/game.32x")
        print("  sh2_linker.py disasm/sh2_slave_consolidated.asm build/sh2_slave.bin --inject 0x20650")
        sys.exit(1)

    asm_file = sys.argv[1]
    output_bin = sys.argv[2]

    rom_file = None
    inject_offset = 0x20650

    # Parse optional arguments
    for i in range(3, len(sys.argv)):
        if sys.argv[i] == '--rom' and i + 1 < len(sys.argv):
            rom_file = sys.argv[i + 1]
        elif sys.argv[i] == '--inject' and i + 1 < len(sys.argv):
            inject_offset = int(sys.argv[i + 1], 0)  # Support 0x hex notation

    linker = SH2Linker(asm_file, output_bin, rom_file, inject_offset)
    linker.run()


if __name__ == '__main__':
    main()
