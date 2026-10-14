#!/usr/bin/env python3
"""Decode 4 SH2 command handlers from VRD 32X ROM with full literal pool resolution."""

import struct
import sys

ROM_PATH = "build/vr_rebuild.32x"

# SH2 address = file_offset + 0x02000000
SH2_BASE = 0x02000000

# Known function addresses
KNOWN_FUNCS = {
    0x060043FC: "completion_handler (clr COMM0_HI, set COMM1_LO.0)",
    0x06004448: "DMAC_FIFO_setup",
    0x060044F6: "scene_init_sub",
    0x06004480: "unknown_04480",
    0x0600252C: "SRAM_copy (1748B -> $C0000000)",
    0x060024DC: "entity_loop",
    0x060032D4: "main_coordinator",
    0x06004300: "buffer_clear (~82KB)",
    0x06004334: "unknown_04334 (from cmd $01)",
    0x06000BBC: "unknown_00BBC",
    0x06000DC8: "unknown_00DC8",
    0x060022BC: "unknown_022BC",
    0x06000FA8: "slave_rendering_entry (cmd $02)",
    0x020608:   "slave_dispatch_loop?",  # SDRAM
}

KNOWN_ADDRS = {
    0x20004020: "COMM0 (cache-through base)",
    0x20004021: "COMM0_LO",
    0x20004022: "COMM1_HI",
    0x20004023: "COMM1_LO",
    0x20004024: "COMM2_HI",
    0x20004025: "COMM2_LO",
    0x20004026: "COMM3_HI",
    0x20004027: "COMM3_LO",
    0x20004028: "COMM4_HI",
    0x20004029: "COMM4_LO",
    0x2000402A: "COMM5_HI",
    0x2000402B: "COMM5_LO",
    0x2000402C: "COMM6_HI",
    0x2000402D: "COMM6_LO",
    0x2000402E: "COMM7_HI",
    0x2000402F: "COMM7_LO",
    0xC0000000: "on-chip SRAM base",
    0xFFFFFE92: "CCR (cache control)",
    0xFFFFFE10: "DMAC SAR0",
    0xFFFFFE11: "DMAC SAR0+1",
    0xFFFFFE14: "DMAC DAR0",
    0xFFFFFE18: "DMAC TCR0",
    0xFFFFFE1C: "DMAC CHCR0",
    0xFFFFFE71: "DMAC DMAOR",
    0xFFFFFEA0: "FRT TIER",
    0xFFFFFEA2: "FRT FTCSR",
    0xFFFFFEB0: "WDT WTCSR",
    0xFFFF8000: "Frame Buffer base",
}

def read_rom(path):
    with open(path, "rb") as f:
        return f.read()

def file_to_sh2(offset):
    """Convert file offset to SH2 CPU address."""
    return offset + SH2_BASE

def sh2_to_file(addr):
    """Convert SH2 CPU address to file offset (for SDRAM addresses)."""
    if 0x06000000 <= addr <= 0x0603FFFF:
        return (addr - 0x06000000) + 0x00020000
    elif 0x02000000 <= addr <= 0x023FFFFF:
        return addr - 0x02000000
    return None

def get_u16(rom, offset):
    return struct.unpack_from(">H", rom, offset)[0]

def get_u32(rom, offset):
    return struct.unpack_from(">I", rom, offset)[0]

def sign_extend_8(val):
    if val & 0x80:
        return val - 256
    return val

def sign_extend_12(val):
    if val & 0x800:
        return val - 4096
    return val

def annotate_addr(addr):
    """Look up address in known tables."""
    if addr in KNOWN_FUNCS:
        return f"  ; = {KNOWN_FUNCS[addr]}"
    if addr in KNOWN_ADDRS:
        return f"  ; = {KNOWN_ADDRS[addr]}"
    # Check SH2 mirror addresses
    if (addr & 0x1FFFFFFF) in KNOWN_ADDRS:
        return f"  ; = {KNOWN_ADDRS[addr & 0x1FFFFFFF]}"
    return ""

def decode_instruction(rom, file_offset, pc):
    """Decode a single SH2 instruction. Returns (mnemonic, size_in_bytes, literal_info)."""
    op = get_u16(rom, file_offset)
    hi4 = (op >> 12) & 0xF
    lo8 = op & 0xFF
    rn = (op >> 8) & 0xF
    rm = (op >> 4) & 0xF

    literal_info = None  # (ea, value, annotation)
    mnemonic = f"dc.w    ${op:04X}"

    # ---- MOV #imm,Rn  (Endd) ----
    if hi4 == 0xE:
        imm = sign_extend_8(lo8)
        mnemonic = f"MOV     #{imm},R{rn}"
        if imm < 0:
            mnemonic += f"  ; = ${imm & 0xFF:02X} -> ${imm & 0xFFFFFFFF:08X}"

    # ---- MOV.W @(disp,PC),Rn  (9ndd) ----
    elif hi4 == 0x9:
        disp = lo8
        ea = (pc + 4) + disp * 2
        ea_file = sh2_to_file(ea)
        val = None
        val_str = "??"
        if ea_file is not None and ea_file + 2 <= len(rom):
            val = get_u16(rom, ea_file)
            val_str = f"${val:04X}"
            # sign extend
            if val & 0x8000:
                sval = val - 0x10000
                val_str += f" (={sval})"
        ann = annotate_addr(val) if val else ""
        mnemonic = f"MOV.W   @(${disp*2:02X},PC),R{rn}  ; [${ea:08X}] = {val_str}{ann}"
        literal_info = ("W", ea, val)

    # ---- MOV.L @(disp,PC),Rn  (Dndd) ----
    elif hi4 == 0xD:
        disp = lo8
        ea = ((pc + 4) & ~3) + disp * 4
        ea_file = sh2_to_file(ea)
        val = None
        val_str = "????????"
        if ea_file is not None and ea_file + 4 <= len(rom):
            val = get_u32(rom, ea_file)
            val_str = f"${val:08X}"
        ann = annotate_addr(val) if val else ""
        mnemonic = f"MOV.L   @(${disp*4:02X},PC),R{rn}  ; [${ea:08X}] = {val_str}{ann}"
        literal_info = ("L", ea, val)

    # ---- MOV.L @(disp,Rm),Rn  (0101nnnnmmmmdddd) ----
    elif hi4 == 0x5:
        disp4 = op & 0xF
        mnemonic = f"MOV.L   @(${disp4*4:02X},R{rm}),R{rn}"

    # ---- MOV.W @(disp,Rm),R0  (10000101mmmmdddd) ----
    elif op & 0xFF00 == 0x8500:
        m = rm
        d = op & 0xF
        mnemonic = f"MOV.W   @(${d*2:02X},R{m}),R0"

    # ---- MOV.B @(disp,Rm),R0  (10000100mmmmdddd) ----
    elif op & 0xFF00 == 0x8400:
        m = rm
        d = op & 0xF
        mnemonic = f"MOV.B   @(${d:02X},R{m}),R0"

    # ---- MOV.L Rm,@(disp,Rn)  (0001nnnnmmmmdddd) ----
    elif hi4 == 0x1:
        disp4 = op & 0xF
        mnemonic = f"MOV.L   R{rm},@(${disp4*4:02X},R{rn})"

    # ---- MOV.W R0,@(disp,Rn) (10000001nnnndddd) ----
    elif op & 0xFF00 == 0x8100:
        n = rm
        d = op & 0xF
        mnemonic = f"MOV.W   R0,@(${d*2:02X},R{n})"

    # ---- MOV.B R0,@(disp,Rn) (10000000nnnndddd) ----
    elif op & 0xFF00 == 0x8000:
        n = rm
        d = op & 0xF
        mnemonic = f"MOV.B   R0,@(${d:02X},R{n})"

    # ---- MOV Rm,Rn  (0110nnnnmmmm0011) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x3:
        mnemonic = f"MOV     R{rm},R{rn}"

    # ---- MOV.L Rm,@Rn (0010nnnnmmmm0010) ----
    elif hi4 == 0x2 and (op & 0xF) == 0x2:
        mnemonic = f"MOV.L   R{rm},@R{rn}"

    # ---- MOV.W Rm,@Rn (0010nnnnmmmm0001) ----
    elif hi4 == 0x2 and (op & 0xF) == 0x1:
        mnemonic = f"MOV.W   R{rm},@R{rn}"

    # ---- MOV.B Rm,@Rn (0010nnnnmmmm0000) ----
    elif hi4 == 0x2 and (op & 0xF) == 0x0:
        mnemonic = f"MOV.B   R{rm},@R{rn}"

    # ---- MOV.L @Rm,Rn (0110nnnnmmmm0010) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x2:
        mnemonic = f"MOV.L   @R{rm},R{rn}"

    # ---- MOV.W @Rm,Rn (0110nnnnmmmm0001) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x1:
        mnemonic = f"MOV.W   @R{rm},R{rn}"

    # ---- MOV.B @Rm,Rn (0110nnnnmmmm0000) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x0:
        mnemonic = f"MOV.B   @R{rm},R{rn}"

    # ---- MOV.L Rm,@-Rn (0010nnnnmmmm0110) ----
    elif hi4 == 0x2 and (op & 0xF) == 0x6:
        mnemonic = f"MOV.L   R{rm},@-R{rn}"

    # ---- MOV.L @Rm+,Rn (0110nnnnmmmm0110) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x6:
        mnemonic = f"MOV.L   @R{rm}+,R{rn}"

    # ---- MOV.W @Rm+,Rn (0110nnnnmmmm0101) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x5:
        mnemonic = f"MOV.W   @R{rm}+,R{rn}"

    # ---- MOV.B @Rm+,Rn (0110nnnnmmmm0100) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x4:
        mnemonic = f"MOV.B   @R{rm}+,R{rn}"

    # ---- MOV.W Rm,@-Rn (0010nnnnmmmm0101) ----
    elif hi4 == 0x2 and (op & 0xF) == 0x5:
        mnemonic = f"MOV.W   R{rm},@-R{rn}"

    # ---- MOV.B Rm,@-Rn (0010nnnnmmmm0100) ----
    elif hi4 == 0x2 and (op & 0xF) == 0x4:
        mnemonic = f"MOV.B   R{rm},@-R{rn}"

    # ---- SWAP.W Rm,Rn (0110nnnnmmmm1001) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x9:
        mnemonic = f"SWAP.W  R{rm},R{rn}"

    # ---- SWAP.B Rm,Rn (0110nnnnmmmm1000) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x8:
        mnemonic = f"SWAP.B  R{rm},R{rn}"

    # ---- EXTU.W Rm,Rn (0110nnnnmmmm1101) ----
    elif hi4 == 0x6 and (op & 0xF) == 0xD:
        mnemonic = f"EXTU.W  R{rm},R{rn}"

    # ---- EXTU.B Rm,Rn (0110nnnnmmmm1100) ----
    elif hi4 == 0x6 and (op & 0xF) == 0xC:
        mnemonic = f"EXTU.B  R{rm},R{rn}"

    # ---- EXTS.W Rm,Rn (0110nnnnmmmm1111) ----
    elif hi4 == 0x6 and (op & 0xF) == 0xF:
        mnemonic = f"EXTS.W  R{rm},R{rn}"

    # ---- EXTS.B Rm,Rn (0110nnnnmmmm1110) ----
    elif hi4 == 0x6 and (op & 0xF) == 0xE:
        mnemonic = f"EXTS.B  R{rm},R{rn}"

    # ---- ADD Rm,Rn (0011nnnnmmmm1100) ----
    elif hi4 == 0x3 and (op & 0xF) == 0xC:
        mnemonic = f"ADD     R{rm},R{rn}"

    # ---- ADD #imm,Rn (0111nnnniiiiiiii) ----
    elif hi4 == 0x7:
        imm = sign_extend_8(lo8)
        mnemonic = f"ADD     #{imm},R{rn}"

    # ---- SUB Rm,Rn (0011nnnnmmmm1000) ----
    elif hi4 == 0x3 and (op & 0xF) == 0x8:
        mnemonic = f"SUB     R{rm},R{rn}"

    # ---- CMP/EQ Rm,Rn (0011nnnnmmmm0000) ----
    elif hi4 == 0x3 and (op & 0xF) == 0x0:
        mnemonic = f"CMP/EQ  R{rm},R{rn}"

    # ---- CMP/GE Rm,Rn (0011nnnnmmmm0011) ----
    elif hi4 == 0x3 and (op & 0xF) == 0x3:
        mnemonic = f"CMP/GE  R{rm},R{rn}"

    # ---- CMP/GT Rm,Rn (0011nnnnmmmm0111) ----
    elif hi4 == 0x3 and (op & 0xF) == 0x7:
        mnemonic = f"CMP/GT  R{rm},R{rn}"

    # ---- CMP/HI Rm,Rn (0011nnnnmmmm0110) ----
    elif hi4 == 0x3 and (op & 0xF) == 0x6:
        mnemonic = f"CMP/HI  R{rm},R{rn}"

    # ---- CMP/HS Rm,Rn (0011nnnnmmmm0010) ----
    elif hi4 == 0x3 and (op & 0xF) == 0x2:
        mnemonic = f"CMP/HS  R{rm},R{rn}"

    # ---- CMP/PL Rn (0100nnnn00010101) ----
    elif hi4 == 0x4 and lo8 == 0x15:
        mnemonic = f"CMP/PL  R{rn}"

    # ---- CMP/PZ Rn (0100nnnn00010001) ----
    elif hi4 == 0x4 and lo8 == 0x11:
        mnemonic = f"CMP/PZ  R{rn}"

    # ---- CMP/EQ #imm,R0  (10001000iiiiiiii) ----
    elif (op >> 8) == 0x88:
        imm = sign_extend_8(lo8)
        mnemonic = f"CMP/EQ  #{imm},R0"

    # ---- TST Rm,Rn (0010nnnnmmmm1000) ----
    elif hi4 == 0x2 and (op & 0xF) == 0x8:
        mnemonic = f"TST     R{rm},R{rn}"

    # ---- TST #imm,R0 (11001000iiiiiiii) ----
    elif (op >> 8) == 0xC8:
        mnemonic = f"TST     #${lo8:02X},R0"

    # ---- AND Rm,Rn (0010nnnnmmmm1001) ----
    elif hi4 == 0x2 and (op & 0xF) == 0x9:
        mnemonic = f"AND     R{rm},R{rn}"

    # ---- AND #imm,R0 (11001001iiiiiiii) ----
    elif (op >> 8) == 0xC9:
        mnemonic = f"AND     #${lo8:02X},R0"

    # ---- OR Rm,Rn (0010nnnnmmmm1011) ----
    elif hi4 == 0x2 and (op & 0xF) == 0xB:
        mnemonic = f"OR      R{rm},R{rn}"

    # ---- OR #imm,R0 (11001011iiiiiiii) ----
    elif (op >> 8) == 0xCB:
        mnemonic = f"OR      #${lo8:02X},R0"

    # ---- XOR Rm,Rn (0010nnnnmmmm1010) ----
    elif hi4 == 0x2 and (op & 0xF) == 0xA:
        mnemonic = f"XOR     R{rm},R{rn}"

    # ---- NOT Rm,Rn (0110nnnnmmmm0111) ----
    elif hi4 == 0x6 and (op & 0xF) == 0x7:
        mnemonic = f"NOT     R{rm},R{rn}"

    # ---- NEG Rm,Rn (0110nnnnmmmm1011) ----
    elif hi4 == 0x6 and (op & 0xF) == 0xB:
        mnemonic = f"NEG     R{rm},R{rn}"

    # ---- SHLL Rn (0100nnnn00000000) ----
    elif hi4 == 0x4 and lo8 == 0x00:
        mnemonic = f"SHLL    R{rn}"

    # ---- SHLR Rn (0100nnnn00000001) ----
    elif hi4 == 0x4 and lo8 == 0x01:
        mnemonic = f"SHLR    R{rn}"

    # ---- SHAL Rn (0100nnnn00100000) ----
    elif hi4 == 0x4 and lo8 == 0x20:
        mnemonic = f"SHAL    R{rn}"

    # ---- SHAR Rn (0100nnnn00100001) ----
    elif hi4 == 0x4 and lo8 == 0x21:
        mnemonic = f"SHAR    R{rn}"

    # ---- SHLL2 Rn (0100nnnn00001000) ----
    elif hi4 == 0x4 and lo8 == 0x08:
        mnemonic = f"SHLL2   R{rn}"

    # ---- SHLR2 Rn (0100nnnn00001001) ----
    elif hi4 == 0x4 and lo8 == 0x09:
        mnemonic = f"SHLR2   R{rn}"

    # ---- SHLL8 Rn (0100nnnn00011000) ----
    elif hi4 == 0x4 and lo8 == 0x18:
        mnemonic = f"SHLL8   R{rn}"

    # ---- SHLR8 Rn (0100nnnn00011001) ----
    elif hi4 == 0x4 and lo8 == 0x19:
        mnemonic = f"SHLR8   R{rn}"

    # ---- SHLL16 Rn (0100nnnn00101000) ----
    elif hi4 == 0x4 and lo8 == 0x28:
        mnemonic = f"SHLL16  R{rn}"

    # ---- SHLR16 Rn (0100nnnn00101001) ----
    elif hi4 == 0x4 and lo8 == 0x29:
        mnemonic = f"SHLR16  R{rn}"

    # ---- ROTL Rn (0100nnnn00000100) ----
    elif hi4 == 0x4 and lo8 == 0x04:
        mnemonic = f"ROTL    R{rn}"

    # ---- ROTR Rn (0100nnnn00000101) ----
    elif hi4 == 0x4 and lo8 == 0x05:
        mnemonic = f"ROTR    R{rn}"

    # ---- ROTCL Rn (0100nnnn00100100) ----
    elif hi4 == 0x4 and lo8 == 0x24:
        mnemonic = f"ROTCL   R{rn}"

    # ---- ROTCR Rn (0100nnnn00100101) ----
    elif hi4 == 0x4 and lo8 == 0x25:
        mnemonic = f"ROTCR   R{rn}"

    # ---- MULU.W Rm,Rn (0010nnnnmmmm1110) ----
    elif hi4 == 0x2 and (op & 0xF) == 0xE:
        mnemonic = f"MULU.W  R{rm},R{rn}"

    # ---- MULS.W Rm,Rn (0010nnnnmmmm1111) ----
    elif hi4 == 0x2 and (op & 0xF) == 0xF:
        mnemonic = f"MULS.W  R{rm},R{rn}"

    # ---- MUL.L Rm,Rn (0000nnnnmmmm0111) ----
    elif hi4 == 0x0 and (op & 0xF) == 0x7:
        mnemonic = f"MUL.L   R{rm},R{rn}"

    # ---- DMULS.L Rm,Rn (0011nnnnmmmm1101) ----
    elif hi4 == 0x3 and (op & 0xF) == 0xD:
        mnemonic = f"DMULS.L R{rm},R{rn}"

    # ---- DMULU.L Rm,Rn (0011nnnnmmmm0101) ----
    elif hi4 == 0x3 and (op & 0xF) == 0x5:
        mnemonic = f"DMULU.L R{rm},R{rn}"

    # ---- STS MACL,Rn (0000nnnn00011010) ----
    elif hi4 == 0x0 and lo8 == 0x1A:
        mnemonic = f"STS     MACL,R{rn}"

    # ---- STS MACH,Rn (0000nnnn00001010) ----
    elif hi4 == 0x0 and lo8 == 0x0A:
        mnemonic = f"STS     MACH,R{rn}"

    # ---- STS PR,Rn (0000nnnn00101010) ----
    elif hi4 == 0x0 and lo8 == 0x2A:
        mnemonic = f"STS     PR,R{rn}"

    # ---- LDS Rm,PR (0100mmmm00101010) ----
    elif hi4 == 0x4 and lo8 == 0x2A:
        mnemonic = f"LDS     R{rn},PR"

    # ---- STS.L PR,@-Rn (0100nnnn00100010) ----
    elif hi4 == 0x4 and lo8 == 0x22:
        mnemonic = f"STS.L   PR,@-R{rn}"

    # ---- LDS.L @Rm+,PR (0100mmmm00100110) ----
    elif hi4 == 0x4 and lo8 == 0x26:
        mnemonic = f"LDS.L   @R{rn}+,PR"

    # ---- STC GBR,Rn (0000nnnn00010010) ----
    elif hi4 == 0x0 and lo8 == 0x12:
        mnemonic = f"STC     GBR,R{rn}"

    # ---- LDC Rm,GBR (0100mmmm00011110) ----
    elif hi4 == 0x4 and lo8 == 0x1E:
        mnemonic = f"LDC     R{rn},GBR"

    # ---- MOV.B R0,@(disp,GBR) (11000000dddddddd) ----
    elif (op >> 8) == 0xC0:
        mnemonic = f"MOV.B   R0,@(${lo8:02X},GBR)"

    # ---- MOV.W R0,@(disp,GBR) (11000001dddddddd) ----
    elif (op >> 8) == 0xC1:
        mnemonic = f"MOV.W   R0,@(${lo8*2:04X},GBR)"

    # ---- MOV.L R0,@(disp,GBR) (11000010dddddddd) ----
    elif (op >> 8) == 0xC2:
        mnemonic = f"MOV.L   R0,@(${lo8*4:04X},GBR)"

    # ---- MOV.B @(disp,GBR),R0 (11000100dddddddd) ----
    elif (op >> 8) == 0xC4:
        mnemonic = f"MOV.B   @(${lo8:02X},GBR),R0"

    # ---- MOV.W @(disp,GBR),R0 (11000101dddddddd) ----
    elif (op >> 8) == 0xC5:
        mnemonic = f"MOV.W   @(${lo8*2:04X},GBR),R0"

    # ---- MOV.L @(disp,GBR),R0 (11000110dddddddd) ----
    elif (op >> 8) == 0xC6:
        mnemonic = f"MOV.L   @(${lo8*4:04X},GBR),R0"

    # ---- MOV.L R0,@(disp,Rn) (0100nnnn????1110) ... actually 0001 ----
    # already handled above

    # ---- BRA disp (1010dddddddddddd) ----
    elif hi4 == 0xA:
        disp = sign_extend_12(op & 0xFFF)
        target = pc + 4 + disp * 2
        ann = annotate_addr(target)
        mnemonic = f"BRA     ${target:08X}{ann}"

    # ---- BSR disp (1011dddddddddddd) ----
    elif hi4 == 0xB:
        disp = sign_extend_12(op & 0xFFF)
        target = pc + 4 + disp * 2
        ann = annotate_addr(target)
        mnemonic = f"BSR     ${target:08X}{ann}"

    # ---- BT disp (10001001dddddddd) ----
    elif (op >> 8) == 0x89:
        disp = sign_extend_8(lo8)
        target = pc + 4 + disp * 2
        ann = annotate_addr(target)
        mnemonic = f"BT      ${target:08X}{ann}"

    # ---- BF disp (10001011dddddddd) ----
    elif (op >> 8) == 0x8B:
        disp = sign_extend_8(lo8)
        target = pc + 4 + disp * 2
        ann = annotate_addr(target)
        mnemonic = f"BF      ${target:08X}{ann}"

    # ---- BT/S disp (10001101dddddddd) ----
    elif (op >> 8) == 0x8D:
        disp = sign_extend_8(lo8)
        target = pc + 4 + disp * 2
        ann = annotate_addr(target)
        mnemonic = f"BT/S    ${target:08X}{ann}"

    # ---- BF/S disp (10001111dddddddd) ----
    elif (op >> 8) == 0x8F:
        disp = sign_extend_8(lo8)
        target = pc + 4 + disp * 2
        ann = annotate_addr(target)
        mnemonic = f"BF/S    ${target:08X}{ann}"

    # ---- JSR @Rn (0100nnnn00001011) ----
    elif hi4 == 0x4 and lo8 == 0x0B:
        mnemonic = f"JSR     @R{rn}"

    # ---- JMP @Rn (0100nnnn00101011) ----
    elif hi4 == 0x4 and lo8 == 0x2B:
        mnemonic = f"JMP     @R{rn}"

    # ---- RTS (000000000000 1011) ----
    elif op == 0x000B:
        mnemonic = "RTS"

    # ---- RTE (0000000000101011) ----
    elif op == 0x002B:
        mnemonic = "RTE"

    # ---- NOP ----
    elif op == 0x0009:
        mnemonic = "NOP"

    # ---- CLRT ----
    elif op == 0x0008:
        mnemonic = "CLRT"

    # ---- SETT ----
    elif op == 0x0018:
        mnemonic = "SETT"

    # ---- CLRMAC ----
    elif op == 0x0028:
        mnemonic = "CLRMAC"

    # ---- DT Rn (0100nnnn00010000) ----
    elif hi4 == 0x4 and lo8 == 0x10:
        mnemonic = f"DT      R{rn}"

    # ---- ADDC Rm,Rn (0011nnnnmmmm1110) ----
    elif hi4 == 0x3 and (op & 0xF) == 0xE:
        mnemonic = f"ADDC    R{rm},R{rn}"

    # ---- SUBC Rm,Rn (0011nnnnmmmm1010) ----
    elif hi4 == 0x3 and (op & 0xF) == 0xA:
        mnemonic = f"SUBC    R{rm},R{rn}"

    # ---- ADDV Rm,Rn (0011nnnnmmmm1111) ----
    elif hi4 == 0x3 and (op & 0xF) == 0xF:
        mnemonic = f"ADDV    R{rm},R{rn}"

    # ---- SUBV Rm,Rn (0011nnnnmmmm1011) ----
    elif hi4 == 0x3 and (op & 0xF) == 0xB:
        mnemonic = f"SUBV    R{rm},R{rn}"

    # ---- MOVT Rn (0000nnnn00101001) ----
    elif hi4 == 0x0 and lo8 == 0x29:
        mnemonic = f"MOVT    R{rn}"

    # ---- MAC.L @Rm+,@Rn+ (0000nnnnmmmm1111) ----
    elif hi4 == 0x0 and (op & 0xF) == 0xF:
        mnemonic = f"MAC.L   @R{rm}+,@R{rn}+"

    # ---- MAC.W @Rm+,@Rn+ (0100nnnnmmmm1111) ----
    elif hi4 == 0x4 and (op & 0xF) == 0xF:
        mnemonic = f"MAC.W   @R{rm}+,@R{rn}+"

    # ---- MOVA @(disp,PC),R0  (11000111dddddddd) ----
    elif (op >> 8) == 0xC7:
        disp = lo8
        ea = ((pc + 4) & ~3) + disp * 4
        ann = annotate_addr(ea)
        mnemonic = f"MOVA    @(${disp*4:02X},PC),R0  ; R0 = ${ea:08X}{ann}"

    # ---- LDC Rm,SR (0100mmmm00001110) ----
    elif hi4 == 0x4 and lo8 == 0x0E:
        mnemonic = f"LDC     R{rn},SR"

    # ---- STC SR,Rn (0000nnnn00000010) ----
    elif hi4 == 0x0 and lo8 == 0x02:
        mnemonic = f"STC     SR,R{rn}"

    # ---- LDC Rm,VBR (0100mmmm00101110) ----
    elif hi4 == 0x4 and lo8 == 0x2E:
        mnemonic = f"LDC     R{rn},VBR"

    # ---- STC VBR,Rn (0000nnnn00100010) ----
    elif hi4 == 0x0 and lo8 == 0x22:
        mnemonic = f"STC     VBR,R{rn}"

    # ---- SLEEP ----
    elif op == 0x001B:
        mnemonic = "SLEEP"

    # ---- MOV.L @(R0,Rm),Rn (0000nnnnmmmm1110) ----
    elif hi4 == 0x0 and (op & 0xF) == 0xE:
        mnemonic = f"MOV.L   @(R0,R{rm}),R{rn}"

    # ---- MOV.W @(R0,Rm),Rn (0000nnnnmmmm1101) ----
    elif hi4 == 0x0 and (op & 0xF) == 0xD:
        mnemonic = f"MOV.W   @(R0,R{rm}),R{rn}"

    # ---- MOV.B @(R0,Rm),Rn (0000nnnnmmmm1100) ----
    elif hi4 == 0x0 and (op & 0xF) == 0xC:
        mnemonic = f"MOV.B   @(R0,R{rm}),R{rn}"

    # ---- MOV.L Rm,@(R0,Rn) (0000nnnnmmmm0110) ----
    elif hi4 == 0x0 and (op & 0xF) == 0x6:
        mnemonic = f"MOV.L   R{rm},@(R0,R{rn})"

    # ---- MOV.W Rm,@(R0,Rn) (0000nnnnmmmm0101) ----
    elif hi4 == 0x0 and (op & 0xF) == 0x5:
        mnemonic = f"MOV.W   R{rm},@(R0,R{rn})"

    # ---- MOV.B Rm,@(R0,Rn) (0000nnnnmmmm0100) ----
    elif hi4 == 0x0 and (op & 0xF) == 0x4:
        mnemonic = f"MOV.B   R{rm},@(R0,R{rn})"

    # ---- XTRCT Rm,Rn (0010nnnnmmmm1101) ----
    elif hi4 == 0x2 and (op & 0xF) == 0xD:
        mnemonic = f"XTRCT   R{rm},R{rn}"

    return mnemonic, 2, literal_info


def decode_handler(rom, file_offset, max_instructions=120, label="Handler"):
    """Decode a handler starting at file_offset. Stop at RTS delay slot or JMP delay slot or max."""
    print(f"\n{'='*100}")
    print(f"  {label}")
    print(f"  File offset: ${file_offset:06X}  |  SH2 addr: ${file_to_sh2(file_offset):08X}")
    print(f"{'='*100}")

    literals_used = {}  # ea -> (type, value)
    branch_targets = set()

    # First pass: collect literals and branch targets
    off = file_offset
    for i in range(max_instructions):
        if off + 2 > len(rom):
            break
        pc = file_to_sh2(off)
        op = get_u16(rom, off)
        hi4 = (op >> 12) & 0xF

        # MOV.W @(disp,PC)
        if hi4 == 0x9:
            disp = op & 0xFF
            ea = (pc + 4) + disp * 2
            ea_file = sh2_to_file(ea)
            if ea_file and ea_file + 2 <= len(rom):
                literals_used[ea] = ("W", get_u16(rom, ea_file))
        # MOV.L @(disp,PC)
        elif hi4 == 0xD:
            disp = op & 0xFF
            ea = ((pc + 4) & ~3) + disp * 4
            ea_file = sh2_to_file(ea)
            if ea_file and ea_file + 4 <= len(rom):
                literals_used[ea] = ("L", get_u32(rom, ea_file))

        off += 2

    # Second pass: actual decode and print
    off = file_offset
    found_end = False
    delay_slot_next = False

    for i in range(max_instructions):
        if off + 2 > len(rom):
            break

        pc = file_to_sh2(off)
        op = get_u16(rom, off)

        mnemonic, size, lit = decode_instruction(rom, off, pc)

        # Check if this address is in literal pool territory
        if pc in literals_used:
            lt, lv = literals_used[pc]
            if lt == "L":
                print(f"  ${pc:08X}:  {op:04X} ", end="")
                op2 = get_u16(rom, off+2) if off+2 < len(rom) else 0
                print(f"{op2:04X}    .long   ${lv:08X}{annotate_addr(lv)}")
                off += 4
                continue
            else:
                print(f"  ${pc:08X}:  {op:04X}          .word   ${lv:04X}")
                off += 2
                continue

        print(f"  ${pc:08X}:  {op:04X}          {mnemonic}")

        if delay_slot_next:
            if found_end:
                print(f"  --- end of handler (RTS/JMP + delay slot) ---")
                break

        # Check for termination
        if op == 0x000B:  # RTS
            found_end = True
            delay_slot_next = True
        elif (op >> 8) == 0x40 and (op & 0xFF) == 0x2B:  # JMP @Rn
            found_end = True
            delay_slot_next = True
        elif (op >> 12) == 0xA:  # BRA (unconditional)
            # BRA with no way back = end (but we continue to show delay slot)
            delay_slot_next = True
        else:
            delay_slot_next = False

        off += size

    if not found_end and not delay_slot_next:
        print(f"  --- reached {max_instructions} instructions without finding end ---")

    # Summary of literal pool values
    if literals_used:
        print(f"\n  Literal Pool Summary:")
        for ea in sorted(literals_used.keys()):
            lt, val = literals_used[ea]
            ann = annotate_addr(val)
            if lt == "L":
                print(f"    [${ea:08X}] .long ${val:08X}{ann}")
            else:
                print(f"    [${ea:08X}] .word ${val:04X}{ann}")


def main():
    rom = read_rom(ROM_PATH)
    print(f"ROM loaded: {len(rom)} bytes ({len(rom)/1024/1024:.1f} MB)")
    print(f"SH2 address mapping: file $000000 = SH2 $02000000")

    # Handler $00 — Default/idle
    decode_handler(rom, 0x020490, max_instructions=30,
                   label="Handler $00 — Default/Idle (7+ jump table entries)")

    # Handler $04
    decode_handler(rom, 0x0212CC, max_instructions=150,
                   label="Handler $04 — Unknown (large, expected JMP tail-call)")

    # Handler $05
    decode_handler(rom, 0x021924, max_instructions=150,
                   label="Handler $05 — Unknown (large)")

    # Handler $06
    decode_handler(rom, 0x021A0C, max_instructions=150,
                   label="Handler $06 — Unknown")

    # Also dump raw hex for handler $00 to sanity check
    print(f"\n{'='*100}")
    print(f"  Raw hex dump — Handler $00 at file offset $020490")
    print(f"{'='*100}")
    off = 0x020490
    for row in range(4):
        addr = file_to_sh2(off + row*16)
        hexbytes = " ".join(f"{rom[off+row*16+j]:02X}{rom[off+row*16+j+1]:02X}" for j in range(0, 16, 2))
        print(f"  ${addr:08X}:  {hexbytes}")


if __name__ == "__main__":
    main()
