# Next Steps - SH2 Code Analysis

**Session Date**: 2026-01-06
**Status**: SH2 Master entry point located!

---

## 🎯 Major Breakthrough Today

We successfully located the SH2 Master entry point:
- **Location**: ROM offset **0x288**
- **SH2 Address**: `$06000288` (uncached ROM access)
- **Discovery**: Found via Boot ROM lookup at ROM offset 0x3E4

---

## 📋 Immediate Next Actions

### 1. Disassemble SH2 Master Entry Code

If you have the ROM file, run:

```bash
# Disassemble first 256 bytes of Master code
python3 tools/sh2_disasm.py virtua_racing.32x 0x288 256

# Or use hexdump to examine raw bytes
hexdump -C virtua_racing.32x -s 0x288 -n 256
```

**What to look for:**
- Stack pointer setup (`MOV.L @(disp,PC),R15`)
- Register initialization
- COMM register address loads
- "M_OK" string or its address
- Jump to main loop

### 2. Find "M_OK" Handshake Code

Search for the ASCII string "M_OK" (0x4D5F4F4B):

```bash
python3 -c "
data = open('virtua_racing.32x', 'rb').read()
target = 0x4D5F4F4B.to_bytes(4, 'big')
for i in range(len(data) - 3):
    if data[i:i+4] == target:
        print(f'Found M_OK at offset 0x{i:X}')
"
```

### 3. Verify SH2 Slave Entry Point

The address at ROM 0x3E8 is `0x06000000`, which seems unusual. Check:

```bash
# Examine ROM start (possible Slave entry)
python3 tools/sh2_disasm.py virtua_racing.32x 0x000 256

# Check if there's a different Slave entry nearby
hexdump -C virtua_racing.32x -s 0x3E8 -n 32
```

Possible explanations:
- Slave might use a different lookup mechanism
- ROM 0x3EC might actually be the Slave entry
- Both CPUs might share initialization code

---

## 🔧 Tools Available

### Disassemblers
- `tools/m68k_disasm.py` - 68000 disassembler (60+ opcodes)
- `tools/sh2_disasm.py` - SH2 disassembler (basic instruction set)
- `tools/analyze_rom.py` - ROM structure analyzer
- `tools/find_code_sections.py` - Code vs data classifier
- `tools/find_sh2_entry.py` - SH2 entry point locator

### Analysis Scripts
```bash
# Find all COMM register references in SH2 code
# COMM0 SH2 address: 0x20004020
python3 tools/sh2_disasm.py virtua_racing.32x 0x288 2048 | grep "20004020"

# Search for SDRAM addresses (0x22xxxxxx)
python3 -c "
import struct
data = open('virtua_racing.32x', 'rb').read()
for i in range(0x288, 0x288 + 2048, 4):
    val = struct.unpack('>I', data[i:i+4])[0]
    if 0x22000000 <= val < 0x22040000:
        print(f'0x{i:X}: SDRAM addr 0x{val:08X}')
"
```

---

## 📊 What We Know

### 68K Side (Complete Understanding)
- ✅ Entry at $8803F0
- ✅ MARS security check
- ✅ 32X adapter initialization
- ✅ Code copy to RAM at $FF0000
- ✅ Wait for SH2 "M_OK" and "S_OK" at ROM 0x808
- ✅ Write 0 to COMM0/COMM4 to start SH2s
- ✅ V-INT handler at $881684
- ✅ H-INT handler at $88170A

### SH2 Side (Partial Understanding)
- ✅ Master entry point: ROM 0x288
- ⏳ Slave entry point: ROM 0x000 (needs verification)
- ❓ Initialization code structure
- ❓ Main rendering loop location
- ❓ Polygon transformation algorithm
- ❓ Frame buffer management
- ❓ Master/Slave work distribution

---

## 📁 Documentation Structure

```
analysis/
├── README.md                    # Master index (updated)
├── INITIALIZATION_SEQUENCE.md   # 68K boot process (complete)
├── MEMORY_MAP.md                # Memory layout (complete)
├── SH2_CODE_HUNT.md             # Entry point search (complete)
├── SH2_MASTER_CODE.md           # Master analysis (framework ready)
└── ROM_STRUCTURE.md             # Early analysis (needs update)

tools/
├── m68k_disasm.py               # 68K disassembler (enhanced)
├── sh2_disasm.py                # SH2 disassembler
├── find_sh2_entry.py            # Entry point finder
└── (other tools...)

disasm/
├── m68k_header.asm              # ROM header (complete, 512 bytes)
└── (future: sh2_master.asm, sh2_slave.asm)
```

---

## 🎯 Session Goals

### This Week
1. **Disassemble Master init** - First 512 bytes from 0x288
2. **Find main loop** - Where does rendering actually happen?
3. **Verify Slave entry** - Confirm Slave startup mechanism
4. **Map SDRAM layout** - Document memory usage

### This Month
1. **Complete SH2 Master disassembly** - Full code flow
2. **Complete SH2 Slave disassembly** - Parallel rendering
3. **Document 3D pipeline** - Transformation → Projection → Rasterization
4. **Identify bottlenecks** - Performance optimization targets

### Long Term
1. **Full game disassembly** - All code documented
2. **Optimization implementation** - Enhanced rendering
3. **FPS improvements** - Smoother gameplay
4. **Knowledge preservation** - Complete documentation

---

## 💡 Key Questions to Answer

### Immediate
1. **What's the first instruction at 0x288?** - Stack setup? Jump?
2. **Where is R15 (stack pointer) set?** - SDRAM address?
3. **Where is "M_OK" written?** - Find the handshake code
4. **Where's the main loop?** - Jump target after init

### Technical
5. **How is SDRAM organized?** - Stack, buffers, shared data layout
6. **How do Master/Slave coordinate?** - Locking mechanism?
7. **What's the rendering order?** - Transformation pipeline stages
8. **Where's the frame buffer written?** - Direct writes or VDP?

### Optimization
9. **Where are the bottlenecks?** - CPU-bound? Memory-bound?
10. **Can we parallelize more?** - Better workload distribution?
11. **Cache usage?** - Cached vs uncached access patterns
12. **Can we optimize transforms?** - Matrix multiplication improvements?

---

## 📚 Reference Materials

### Hardware
- [32X Hardware Manual](docs/32x-hardware-manual.md) - Complete specs
- [32X Technical Info](docs/32x-technical-info-attachment1.md) - Code examples
- Hitachi SH7604 Manual - SH2 instruction set (external)

### Our Analysis
- [SH2_CODE_HUNT.md](analysis/SH2_CODE_HUNT.md) - Entry point discovery
- [SH2_MASTER_CODE.md](analysis/SH2_MASTER_CODE.md) - Master analysis framework
- [MEMORY_MAP.md](analysis/MEMORY_MAP.md) - Address space layout

---

## 🚀 Quick Start Commands

```bash
# If ROM is available:
cd /mnt/data/src/32x-playground

# 1. Examine Master entry point
python3 tools/sh2_disasm.py virtua_racing.32x 0x288 256

# 2. Look for strings in SH2 code
strings -tx virtua_racing.32x | grep -i "ok\|master\|slave"

# 3. Check Slave entry
python3 tools/sh2_disasm.py virtua_racing.32x 0x000 256

# 4. Find entry point table
hexdump -C virtua_racing.32x -s 0x3E0 -n 32
```

---

## ✅ Today's Achievements

1. ✅ Fixed M68K disassembler (60+ new opcodes)
2. ✅ Completed 68K init code analysis
3. ✅ Discovered SH2 Boot ROM mechanism
4. ✅ Located SH2 Master entry point (ROM 0x288)
5. ✅ Documented handshake protocol
6. ✅ Created SH2 Master analysis framework
7. ✅ Updated all documentation

**Result**: We now have a clear path to understanding the 3D engine!

---

**Last Updated**: 2026-01-06 23:59
**Next Session**: Disassemble SH2 Master code and map the rendering pipeline

