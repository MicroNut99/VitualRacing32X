#!/usr/bin/env python3
"""Keep Sega's ROM bytes out of the source tree.

Section files in disasm/sections_src/ hold the hand-written parts (includes,
org lines, edited code). Every run of plain ROM words is one line:

        ROMDATA $start,$end        ; [start, end) ROM offsets

expand: ROM + disasm/sections_src/*.asm -> disasm/sections/*.asm, the same
        dc.w lines the disassembly had ("dc.w $XXXX ; $ADDR").
strip:  the other way (used once to make sections_src from the original
        disassembly); only lines whose word matches the ROM are replaced.

usage: romdata.py expand ROM SRC_DIR OUT_DIR
       romdata.py strip  ROM IN_DIR  SRC_DIR
"""
import os
import re
import sys

DCW = re.compile(r'^        dc\.w    \$([0-9A-F]{4})        ; \$([0-9A-F]{6})$')
MARK = re.compile(r'^        ROMDATA \$([0-9A-F]+),\$([0-9A-F]+)')


def dcw_line(rom, addr):
    return '        dc.w    $%02X%02X        ; $%06X' % (rom[addr], rom[addr + 1], addr)


def strip_file(rom, text):
    out = []
    run = None  # [start, end)

    def flush():
        nonlocal run
        if run:
            out.append('        ROMDATA $%06X,$%06X' % (run[0], run[1]))
            run = None

    for line in text.split('\n'):
        m = DCW.match(line)
        if m:
            addr = int(m.group(2), 16)
            word = int(m.group(1), 16)
            if addr + 2 <= len(rom) and rom[addr] == word >> 8 and rom[addr + 1] == word & 255:
                if run and run[1] == addr:
                    run[1] += 2
                    continue
                flush()
                run = [addr, addr + 2]
                continue
        flush()
        out.append(line)
    flush()
    return '\n'.join(out)


def expand_file(rom, text):
    out = []
    for line in text.split('\n'):
        m = MARK.match(line)
        if m:
            a, b = int(m.group(1), 16), int(m.group(2), 16)
            if b > len(rom) or a >= b or (a | b) & 1:
                sys.exit('bad ROMDATA range %s' % line.strip())
            out.extend(dcw_line(rom, x) for x in range(a, b, 2))
        else:
            out.append(line)
    return '\n'.join(out)


def main():
    if len(sys.argv) != 5 or sys.argv[1] not in ('expand', 'strip'):
        sys.exit(__doc__)
    mode, rom_path, src, dst = sys.argv[1:]
    rom = open(rom_path, 'rb').read()
    os.makedirs(dst, exist_ok=True)
    fn = expand_file if mode == 'expand' else strip_file
    for name in sorted(os.listdir(src)):
        if not name.endswith('.asm'):
            continue
        with open(os.path.join(src, name), newline='') as f:
            text = f.read()
        with open(os.path.join(dst, name), 'w', newline='') as f:
            f.write(fn(rom, text))


if __name__ == '__main__':
    main()
