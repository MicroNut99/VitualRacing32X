#!/usr/bin/env python3
"""
SH2 Linker Phase 4+ - Multi-Region ROM Injection
Handles split injection: Phase 1 at boot location + extended functions in safe space

Usage:
    python3 sh2_linker_phase4.py <input_asm> <output_binary> --rom rom_file
"""

import sys
import struct
import subprocess
import os
from pathlib import Path

class SH2LinkerPhase4:
    def __init__(self, asm_file, output_bin, rom_file=None):
        self.asm_file = asm_file
        self.output_bin = output_bin
        self.rom_file = rom_file
        self.object_file = output_bin.replace('.bin', '.o')

        # Multi-region configuration
        self.regions = {
            'phase1_boot': {
                'offset': 0x20650,
                'max_size': 200,
                'functions': ['slave_main_loop', 'slave_process_polygons', 'sync_base_addr']
            },
            'phase3_extended': {
                'offset': 0x2F6000,
                'max_size': 169984,
                'functions': ['parse_polygon_bounds', 'slave_func_029', 'slave_func_032', 'slave_func_033', 'slave_func_034', 'slave_func_023']
            }
        }

        self.symbols = {}
        self.binary = b''

    def assemble(self):
        """Assemble SH2 code"""
        print(f"[*] Assembling: {self.asm_file}")
        result = subprocess.run(
            ['sh-elf-as', '-o', self.object_file, self.asm_file],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"[!] Assembly failed: {result.stderr}")
            sys.exit(1)
        print(f"[+] Object file created")

    def extract_binary(self):
        """Convert object file to binary"""
        print(f"[*] Extracting binary")
        result = subprocess.run(
            ['sh-elf-objcopy', '-O', 'binary', self.object_file, self.output_bin],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"[!] Extraction failed: {result.stderr}")
            sys.exit(1)

        with open(self.output_bin, 'rb') as f:
            self.binary = f.read()
        print(f"[+] Binary extracted: {len(self.binary)} bytes")

    def extract_symbols(self):
        """Extract symbol table"""
        print(f"[*] Extracting symbols")
        result = subprocess.run(
            ['sh-elf-nm', '-n', self.object_file],
            capture_output=True,
            text=True
        )

        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            parts = line.split()
            if len(parts) >= 3:
                try:
                    offset = int(parts[0], 16)
                    symbol = parts[2]
                    self.symbols[symbol] = offset
                except ValueError:
                    pass

        print(f"[+] Found {len(self.symbols)} symbols")

    def allocate_regions(self):
        """Determine which functions go to which ROM region"""
        print(f"\n[*] Allocating functions to ROM regions")

        # For Phase 4, we'll split: Phase 1 at 0x20650, everything else at 0x2F6000
        allocation = {
            'phase1_boot': [],
            'phase3_extended': []
        }

        for symbol, offset in sorted(self.symbols.items(), key=lambda x: x[1]):
            # Phase 1 functions stay at boot location
            if symbol in ['slave_main_loop', 'slave_process_polygons', '.wait_for_work',
                          'sync_base_addr', 'ready_magic', 'work_magic', 'done_magic']:
                allocation['phase1_boot'].append((symbol, offset))
            # Everything else goes to extended space
            elif not symbol.startswith('SYNC_BASE') and not symbol.startswith('_'):
                allocation['phase3_extended'].append((symbol, offset))

        print("\n[+] Allocation:")
        for region, funcs in allocation.items():
            print(f"    {region}: {len(funcs)} symbols")
            for sym, off in funcs[:5]:
                print(f"      - {sym} @ 0x{off:04X}")
            if len(funcs) > 5:
                print(f"      ... and {len(funcs) - 5} more")

        return allocation

    def print_memory_map(self):
        """Print detailed memory map"""
        print("\n" + "="*80)
        print("SH2 PHASE 4 MEMORY MAP - Multi-Region Injection")
        print("="*80)

        print("\nRegion 1: BOOT CRITICAL (Phase 1)")
        print(f"  ROM Offset: 0x{self.regions['phase1_boot']['offset']:06X}")
        print(f"  Max Size:   {self.regions['phase1_boot']['max_size']} bytes")
        print(f"  Purpose:    Slave work dispatcher (must fit in boot space)")

        print("\nRegion 2: EXTENDED CODE (Phase 3.1-3.4)")
        print(f"  ROM Offset: 0x{self.regions['phase3_extended']['offset']:06X}")
        print(f"  Max Size:   {self.regions['phase3_extended']['max_size']} bytes")
        print(f"  Purpose:    Rendering functions (func_029-034, func_023)")

        print("\nSymbols by Region:")
        print("-" * 80)

        for symbol in sorted(self.symbols.keys()):
            offset = self.symbols[symbol]
            if symbol in ['slave_main_loop', 'slave_process_polygons']:
                rom_addr = self.regions['phase1_boot']['offset'] + offset
                region = "PHASE1"
            else:
                rom_addr = self.regions['phase3_extended']['offset'] + offset
                region = "PHASE3"

            if not symbol.startswith('.'):
                print(f"  {symbol:30s}  Offset: 0x{offset:04X}  ROM: 0x{rom_addr:06X}  [{region}]")

        print("\n" + "="*80)

    def inject_into_rom(self):
        """Inject binaries into ROM at both locations with address relocation"""
        if not self.rom_file or not os.path.exists(self.rom_file):
            print("[!] No valid ROM file for injection")
            return

        print(f"\n[*] Injecting into ROM: {self.rom_file}")

        # Prepare binary with relocated addresses for split injection
        binary_to_inject = bytearray(self.binary)
        self._relocate_addresses(binary_to_inject)

        # Read original ROM
        with open(self.rom_file, 'r+b') as f:
            # Phase 1: Inject at boot location (0x20650)
            boot_size = 200  # Conservative Phase 1 size
            f.seek(self.regions['phase1_boot']['offset'])
            f.write(binary_to_inject[:boot_size])
            print(f"[+] Phase 1 injected at 0x{self.regions['phase1_boot']['offset']:06X} ({boot_size} bytes)")

            # Phase 3: Inject extended functions at safe location
            extended = binary_to_inject[boot_size:]
            if len(extended) > 0:
                f.seek(self.regions['phase3_extended']['offset'])
                f.write(extended)
                print(f"[+] Phase 3 injected at 0x{self.regions['phase3_extended']['offset']:06X} ({len(extended)} bytes)")

        print("\n[+] Multi-region injection complete!")

    def _relocate_addresses(self, binary):
        """Patch address literals for split injection

        Phase 3 functions are injected at 0x2F6000, but address literals
        were calculated as if the entire binary is there. This adjusts them
        to account for Phase 1 being split off and placed at 0x20650.
        """
        boot_size = 200
        phase1_offset = 0x020650  # SH2 address space
        phase3_offset = 0x02F6000  # SH2 address space

        # Known address literal locations in the binary (from assembly)
        # These are .long fields that contain ROM addresses
        address_literal_locs = [
            (0x01E0, 'func_023_addr'),  # Points to slave_func_023
            (0x01E4, 'func_029_addr'),  # Points to slave_func_029
        ]

        for literal_offset, name in address_literal_locs:
            if literal_offset >= len(binary) - 4:
                continue  # Skip if beyond binary size

            # Extract the current address (big-endian 32-bit)
            current_addr = struct.unpack('>I', binary[literal_offset:literal_offset+4])[0]

            # Determine if this is a Phase 3 address
            # Phase 3 addresses are in range 0x02F60000-0x02F70000
            if phase3_offset <= current_addr < 0x02F70000:
                # This points to a Phase 3 location
                # Calculate binary offset from the Phase 3 base address
                bin_offset_in_phase3 = current_addr - phase3_offset

                # In the actual binary, Phase 3 functions start at boot_size
                bin_offset_in_full = boot_size + bin_offset_in_phase3

                # Recalculate final ROM address
                # Phase 3 functions will be at phase3_offset + their offset within Phase 3
                new_offset_in_phase3 = bin_offset_in_full - boot_size
                new_addr = phase3_offset + new_offset_in_phase3

                binary[literal_offset:literal_offset+4] = struct.pack('>I', new_addr)
                print(f"[*] Relocated {name}: 0x{current_addr:08X} -> 0x{new_addr:08X}")
            elif phase1_offset <= current_addr < phase1_offset + 256:
                # This points to Phase 1 - no relocation needed
                pass

    def generate_makefile_snippet(self):
        """Generate Makefile snippet for build integration"""
        print("\n" + "="*80)
        print("Makefile Integration")
        print("="*80 + "\n")

        print("""# Phase 4+ Multi-Region SH2 Linker
SH2_CONSOLIDATED = disasm/sh2_slave_consolidated.asm
SH2_PHASE1_BIN = build/sh2_slave_phase1.bin
SH2_PHASE3_BIN = build/sh2_slave_phase3.bin

phase4-rom: $(SH2_CONSOLIDATED)
\tpython3 tools/sh2_linker_phase4.py $(SH2_CONSOLIDATED) \\
\t    build/sh2_slave_phase4.bin --rom $(OUTPUT_ROM)

# Alternative: manual dd injection
inject-phase4-manual:
\t# Phase 1 at boot
\tdd if=$(SH2_PHASE1_BIN) of=$(OUTPUT_ROM) bs=1 seek=$$((0x20650)) conv=notrunc
\t# Phase 3 at safe location
\tdd if=$(SH2_PHASE3_BIN) of=$(OUTPUT_ROM) bs=1 seek=$$((0x2F6000)) conv=notrunc
""")

        print("="*80 + "\n")

    def run(self):
        """Execute full linker pipeline"""
        print("\n[*] SH2 Phase 4+ Linker Starting...")

        self.assemble()
        self.extract_binary()
        self.extract_symbols()
        self.allocate_regions()
        self.print_memory_map()
        self.generate_makefile_snippet()

        if self.rom_file:
            self.inject_into_rom()

        print("\n[+] Phase 4 linker complete!")


def main():
    if len(sys.argv) < 3:
        print("Usage: sh2_linker_phase4.py <input.asm> <output.bin> --rom romfile")
        sys.exit(1)

    asm_file = sys.argv[1]
    output_bin = sys.argv[2]
    rom_file = None

    for i in range(3, len(sys.argv)):
        if sys.argv[i] == '--rom' and i + 1 < len(sys.argv):
            rom_file = sys.argv[i + 1]

    linker = SH2LinkerPhase4(asm_file, output_bin, rom_file)
    linker.run()


if __name__ == '__main__':
    main()
