#!/usr/bin/env python3
"""Pad the built ROM to a full 4 MB (0xFF) and write the header checksum.

The header says the ROM ends at $3FFFFF; a shorter file is mapped
differently by some emulators and flash carts. The checksum at $18E is the
16-bit sum of all words from $200 on, as Sega's tools write it.

usage: fixrom.py ROM
"""
import struct
import sys

SIZE = 0x400000

path = sys.argv[1]
d = bytearray(open(path, 'rb').read())
if len(d) > SIZE:
    sys.exit('ROM is bigger than 4 MB')
d += b'\xff' * (SIZE - len(d))
s = sum(struct.unpack('>%dH' % ((SIZE - 0x200) // 2), bytes(d[0x200:]))) & 0xFFFF
d[0x18E:0x190] = struct.pack('>H', s)
open(path, 'wb').write(d)
print('%s: %d bytes, checksum $%04X' % (path, len(d), s))
