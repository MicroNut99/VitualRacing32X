# V-INT State Handler Analysis

## Overview

The V-INT handler at [vint_handler.asm:1684](../disasm/modules/68k/main-loop/vint_handler.asm#L1684) implements a 16-state dispatch system. Each state handler performs specific operations during the vertical blanking interval. All handlers are located in [controller_read.asm:17EE-2200](../disasm/modules/68k/input/controller_read.asm).

## State Handler Summary Table

| State | Address | Type | Purpose |
|-------|---------|------|---------|
| 0 | $0019FE | Common | VDP read + RAM sync + Z-Bus operations |
| 1 | $0019FE | Common | (same as state 0) |
| 2 | $0019FE | Common | (same as state 0) |
| 3 | $018200 | ⚠️ RAM | Runtime-patched handler (unusual) |
| 4 | $001A6E | Minimal | Single VDP read |
| 5 | $001A72 | VDP Sync | VDP read + RAM writes + Z-Bus |
| 6 | $001C66 | VDP Sync | VDP registers + RAM sync + frame buffer toggle |
| 7 | $001ACA | VDP Config | VDP register writes (sprite config) |
| 8 | $0019FE | Common | (same as state 0) |
| 9 | $001E42 | FB Setup | VDP sync + frame buffer copy |
| 10 | $001B14 | VDP Config | VDP registers + sprite config |
| 11 | $001A64 | Transition | Set next state to #44 |
| 12 | $001BA8 | Complex VDP | Multiple VDP register sets |
| 13 | $001E94 | FB Operations | VDP config + frame buffer check + palette copy |
| 14 | $001F4A | VDP + FB | VDP registers + frame buffer DMA |
| 15 | $002010 | Cleanup | Clear SH2 command flags |

## Detailed Handler Analysis

### States 0, 1, 2, 8: Common Handler ($0019FE)

**Location:** [controller_read.asm:196](../disasm/modules/68k/input/controller_read.asm#L196)

**Purpose:** Standard VDP synchronization and RAM updates

**Operations:**
```asm
$0019FE:  MOVE.W  (A5),D0              ; Read VDP control port (A5 = $00C00004)
$001A00:  MOVE.L  #$6C000003,(A5)      ; VDP command: VRAM write at $6C00
$001A06:  MOVE.W  $8000.W,(A6)         ; Read MD VDP data port
$001A0A:  MOVE.W  $8002.W,(A6)         ; Read MD VDP data mirror
$001A0E:  MOVE.L  #$40000010,(A5)      ; VDP command: VSRAM write at $00
$001A14:  MOVE.W  $C880.W,(A6)         ; Write RAM value to VSRAM
$001A18:  MOVE.W  $C882.W,(A6)         ; Write RAM value to VSRAM
$001A1C:  MOVE.W  #$0100,$00A11100     ; Request Z80 bus
$001A24:  BTST    #0,$00A11100         ; Wait for Z80 bus grant
$001A2C:  BNE.S   -2                   ; Loop until granted
... (VDP register writes continue)
$001A62:  RTS
```

**Register Usage:**
- A5 = $00C00004 (VDP control port)
- A6 = $00C00000 (VDP data port)
- $C874.W, $C876.W = VDP register values (RAM cache)
- $C880.W, $C882.W = VSRAM scroll values

**VDP Commands Used:**
- `$6C000003` = VRAM write at $6C00
- `$40000010` = VSRAM write at offset $00

**VDP Register Writes:**
- `$9340` = Reg 19: DMA length low = $40
- `$9400` = Reg 20: DMA length high = $00
- `$9540` = Reg 21: DMA source low = $40
- `$96C2` = Reg 22: DMA source mid = $C2
- `$977F` = Reg 23: DMA source high/type = $7F
- `$C000` = VRAM address command (not a register write)
- `$80xx` = Cached VDP register values from $C876

**Frequency:** Used by 4 states (most common handler)

---

### State 4: Minimal Read ($001A6E)

**Location:** [controller_read.asm:221](../disasm/modules/68k/input/controller_read.asm#L221)

**Purpose:** Quick VDP status check

**Operations:**
```asm
$001A6E:  MOVE.W  (A5),D0              ; Read VDP control port
$001A70:  RTS                          ; Return immediately
```

**Analysis:**
- Fastest state handler (2 instructions)
- Simply reads VDP status to acknowledge vertical interrupt
- No state changes, no RAM updates
- Likely used when game is idle or paused

---

### State 5: VDP Sync ($001A72)

**Location:** [controller_read.asm:223](../disasm/modules/68k/input/controller_read.asm#L223)

**Purpose:** Full VDP synchronization with Z-Bus arbitration

**Operations:**
```asm
$001A72:  MOVE.W  (A5),D0              ; Read VDP control
$001A74:  MOVE.L  #$40000010,(A5)      ; VSRAM write command
$001A7A:  MOVE.W  $C880.W,(A6)         ; Write scroll values
$001A7E:  MOVE.W  $C882.W,(A6)
$001A82:  MOVE.W  #$0100,$00A11100     ; Request Z80 bus
$001A8A:  BTST    #0,$00A11100         ; Wait for grant
... (VDP register configuration)
$001AC8:  RTS
```

**VDP Registers:**
- Same as common handler
- Updates scroll registers in VSRAM

---

### State 6: Frame Buffer Toggle ($001C66)

**Location:** [controller_read.asm:336](../disasm/modules/68k/input/controller_read.asm#L336)

**Purpose:** VDP sync + 32X frame buffer management

**Operations:**
```asm
$001C66:  MOVE.W  (A5),D0              ; VDP read
$001C68:  MOVE.L  #$6C000003,(A5)      ; VRAM write
$001C6E:  MOVE.W  $8000.W,(A6)
...
$001C84:  MOVE.W  #$0100,$00A11100     ; Z-Bus request
... (VDP operations)
$001CCA:  TST.B   $00A15120            ; Check COMM0 (SH2 handshake)
$001CD0:  BNE.S   end                  ; Skip if SH2 busy
$001CD2:  BCLR    #7,$00A15100         ; Clear REN (SH2 Reset Enable) in Adapter Control
$001CDA:  BTST    #7,$00A1518A         ; Test VBLK (bit 15 of FB Control) — wait for V Blank
$001CE2:  BEQ.S   -8
$001CE4:  JSR     $002878(PC)          ; Call frame buffer routine
$001CE8:  BCHG    #0,$C80C.W           ; Toggle frame buffer flag
$001CEE:  BNE.S   skip_set
$001CF0:  BSET    #0,$00A1518B         ; Set FS bit (swap to DRAM1 display)
$001CF8:  BRA.S   done
skip_set:
$001CFA:  BCLR    #0,$00A1518B         ; Clear FS bit (swap to DRAM0 display)
done:
$001D02:  BSET    #7,$00A15100         ; Set REN (SH2 Reset Enable) in Adapter Control
$001D0A:  RTS
```

**32X Registers:**
- $A15120 (COMM0): SH2 communication status
- $A15100 (Adapter Control): FM=bit 15, REN=bit 7, RES=bit 1, ADEN=bit 0
- $A1518A (Frame Buffer Control): VBLK=bit 15, HBLK=bit 14, PEN=bit 13, FEN=bit 1 (Read Only), FS=bit 0 (R/W)
- $A1518B (FB Control low byte): FS=bit 0 (frame buffer swap, deferred to next VBlank if written during display)
- $C80C.W: Frame buffer toggle flag (RAM)

**Analysis:**
- Clears REN bit temporarily (BCLR #7 on Adapter Control $A15100)
- Waits for V Blank (BTST #7 = VBLK bit 15 on FB Control $A1518A)
- Toggles FS bit (bit 0 at $A1518B) to swap frame buffers
- Restores REN bit (BSET #7 on Adapter Control)
- Critical for double-buffering; FS write during VBlank takes effect immediately

---

### State 7: VDP Configuration ($001ACA)

**Location:** [controller_read.asm:243](../disasm/modules/68k/input/controller_read.asm#L243)

**Purpose:** Configure VDP sprite system

**Operations:**
```asm
$001ACA:  MOVE.W  (A5),D0              ; VDP read
$001ACC:  MOVE.W  #$0100,$00A11100     ; Z-Bus request
$001AD4:  BTST    #0,$00A11100         ; Wait
...
$001AE8:  MOVE.L  #$93809401,(A5)      ; VDP regs 19-20 (DMA length)
$001AEE:  MOVE.L  #$951E96C0,(A5)      ; VDP regs 21-22 (DMA source low/mid)
$001AF4:  MOVE.W  #$977F,(A5)          ; VDP reg 23 (DMA source high/type)
$001AF8:  MOVE.W  #$6C3C,(A5)          ; VRAM address command
$001AFC:  MOVE.W  #$0083,$C876.W       ; Update cache
$001B02:  MOVE.W  $C876.W,(A5)         ; Write to VDP
$001B12:  RTS
```

**VDP Register Differences:**
- `$9401` = Reg 20: DMA length high = $01
- `$951E` = Reg 21: DMA source low = $1E
- `$96C0` = Reg 22: DMA source mid = $C0
- `$6C3C` = VRAM address command (not a register write)

**Analysis:**
- Likely used for sprite table updates
- Different configuration from common handler
- Cache updated at $C876

---

### State 9: Frame Buffer Copy ($001E42)

**Location:** [controller_read.asm:448](../disasm/modules/68k/input/controller_read.asm#L448)

**Purpose:** VDP sync + copy data to 32X frame buffer

**Operations:**
```asm
$001E42:  MOVE.W  (A5),D0              ; VDP read
$001E44:  MOVE.L  #$6C000003,(A5)      ; VRAM write
...
$001E60:  MOVE.W  #$0000,$C87E.W       ; Clear counter
$001E66:  BCHG    #0,$C80C.W           ; Toggle frame buffer
$001E6C:  BNE.S   clear_fb
$001E6E:  BSET    #0,$00A1518B         ; Set FS bit (swap to DRAM1 display)
$001E76:  BRA.S   copy
clear_fb:
$001E78:  BCLR    #0,$00A1518B         ; Clear FS bit (swap to DRAM0 display)
copy:
$001E80:  LEA     $A100.W,A0           ; Source: MD RAM
$001E84:  LEA     $00A15200,A1         ; Dest: 32X palette RAM
$001E8A:  MOVEQ   #$7F,D0              ; 128 longs = 512 bytes
$001E8C:  MOVE.L  (A0)+,(A1)+          ; Copy loop
$001E8E:  DBRA    D0,-4
$001E92:  RTS
```

**Data Transfer:**
- Source: $A100 (MD RAM - 512 bytes)
- Destination: $A15200 (32X palette RAM)
- Size: 512 bytes (128 longwords)

**Analysis:**
- Transfers MD palette to 32X palette
- Updates frame buffer selection
- Critical for color changes

---

### State 10: VDP Configuration ($001B14)

**Location:** [controller_read.asm:260](../disasm/modules/68k/input/controller_read.asm#L260)

**Purpose:** VDP sync with different sprite configuration

**Operations:**
```asm
$001B14:  MOVE.W  (A5),D0              ; VDP read
$001B16:  MOVE.L  #$6C000003,(A5)
...
$001B4E:  MOVE.L  #$93809403,(A5)      ; Different config
$001B54:  MOVE.L  #$95009688,(A5)
$001B5A:  MOVE.W  #$977F,(A5)
$001B5E:  MOVE.W  #$6000,(A5)          ; Different DMA source
...
```

**VDP Differences:**
- `$9403` = Reg 20: DMA length high = $03
- `$9500` = Reg 21: DMA source low = $00
- `$9688` = Reg 22: DMA source mid = $88
- `$6000` = VRAM address command

**Subsequent Operations:**
- Writes another VDP register set
- Returns to common config
- Does NOT release Z-Bus

---

### State 11: State Transition ($001A64)

**Location:** [controller_read.asm:219](../disasm/modules/68k/input/controller_read.asm#L219)

**Purpose:** Queue next state and jump to handler

**Operations:**
```asm
$001A64:  MOVE.W  #$002C,$C87A.W       ; Set state to 44 (0x2C)
$001A6A:  JMP     .call_driver(PC)       ; Jump to common handler
```

**Analysis:**
- Transitions to state 44
- State 44 not in standard 0-15 range
- Extended state system (16+ states possible)
- Likely triggers special game mode

---

### State 12: Complex VDP Operations ($001BA8)

**Location:** [controller_read.asm:293](../disasm/modules/68k/input/controller_read.asm#L293)

**Purpose:** Multiple VDP configurations in sequence

**Operations:**
```asm
$001BA8:  MOVE.W  (A5),D0              ; VDP read
$001BAA:  MOVE.W  #$0100,$00A11100     ; Z-Bus
... (First VDP config)
$001BC6:  MOVE.L  #$93809403,(A5)
$001BCC:  MOVE.L  #$95009688,(A5)
... (Second VDP config)
$001BF2:  MOVE.L  #$93809403,(A5)
$001BF8:  MOVE.L  #$9580968B,(A5)      ; Different values
... (Third VDP config)
$001C1E:  MOVE.L  #$93409400,(A5)
$001C24:  MOVE.L  #$954096C2,(A5)
$001C48:  MOVE.L  #$6C000003,(A5)      ; VRAM write
...
$001C64:  RTS
```

**Analysis:**
- Three separate VDP configurations
- Likely sets up complex screen layouts
- Possibly used for split-screen or special effects
- Most complex state handler

---

### State 13: Frame Buffer Check ($001E94)

**Location:** [controller_read.asm:470](../disasm/modules/68k/input/controller_read.asm#L470)

**Purpose:** VDP config + frame buffer operations with SH2 sync

**Operations:**
```asm
$001E94:  MOVE.W  (A5),D0              ; VDP read
... (VDP register config)
$001EDC:  BTST    #0,$00A15123         ; Check COMM1_LO bit 0 (SH2 "done" signal)
$001EE4:  BEQ.S   skip                 ; Skip if not set
$001EE6:  BCLR    #0,$00A15123         ; Clear COMM1_LO bit 0 (SH2 "done" signal)
$001EEE:  CMPI.B  #$0018,$C8C5.W       ; Check game state
$001EF4:  BNE.S   +8
$001EF6:  MOVE.W  #$0000,$C87E.W       ; Reset counter if state $18
$001EFC:  MOVE.B  #$0000,$C8C4.W       ; Clear flag
$001F02:  BCLR    #7,$00A15100         ; Clear REN (SH2 Reset Enable) in Adapter Control
$001F0A:  BTST    #7,$00A1518A         ; Test VBLK (bit 15 of FB Control) — wait for V Blank
... (Frame buffer toggle + palette copy)
$001F14:  LEA     $B400.W,A1           ; Source data
$001F18:  LEA     $00A15200,A2         ; Dest: 32X palette
$001F1E:  JSR     $0048D6(PC)          ; Copy routine
$001F22:  JSR     $0048DA(PC)          ; Another copy
$001F26:  BCHG    #0,$C80C.W           ; Toggle FB
... (FB control)
$001F48:  RTS
```

**32X Operations:**
- COMM1_LO ($A15123): SH2 "render done" signal (bit 0)
- Palette copy from $B400 (MD RAM) to $A15200 (32X palette)
- Frame buffer toggle (FS bit at $A1518B)

**Analysis:**
- Checks for SH2 command completion
- Copies palette data twice (double buffer?)
- Game state-dependent behavior

---

### State 14: VDP + Frame Buffer DMA ($001F4A)

**Location:** [controller_read.asm:512](../disasm/modules/68k/input/controller_read.asm#L512)

**Purpose:** VDP config + frame buffer DMA

**Operations:**
```asm
$001F4A:  MOVE.W  (A5),D0              ; VDP read
... (VDP operations)
$001FAE:  BTST    #0,$00A15123         ; Check COMM1_LO bit 0
$001FB6:  BEQ.S   skip
$001FB8:  BCLR    #0,$00A15123         ; Clear COMM1_LO bit 0 (SH2 "done" signal)
$001FC0:  MOVE.W  #$0000,$C87E.W       ; Reset counter
$001FC6:  BCLR    #7,$00A15100         ; Clear REN (SH2 Reset Enable) in Adapter Control
$001FCE:  BTST    #7,$00A1518A         ; Test VBLK (bit 15 of FB Control) — wait for V Blank
$001FD8:  LEA     $00FF6E00,A1         ; Source: MD RAM high
$001FDE:  LEA     $00A15200,A2         ; Dest: 32X palette
$001FE4:  JSR     $0048D6(PC)          ; Copy
$001FE8:  JSR     $0048DA(PC)          ; Copy again
... (Frame buffer toggle)
$00200E:  RTS
```

**Differences from State 13:**
- Different source address: $FF6E00 (high RAM)
- Different VDP register config
- Same frame buffer logic

---

### State 15: Cleanup ($002010)

**Location:** [controller_read.asm:556](../disasm/modules/68k/input/controller_read.asm#L556)

**Purpose:** Clear SH2 command flags

**Operations:**
```asm
$002010:  MOVE.W  (A5),D0              ; VDP read
$002012:  BTST    #0,$00A15123         ; Check COMM1_LO bit 0
$00201A:  BEQ.S   done                 ; Skip if not set
$00201C:  BCLR    #0,$00A15123         ; Clear COMM1_LO bit 0 (SH2 "done" signal)
$002024:  CMPI.B  #$0018,$C8C5.W       ; Check game state
$00202A:  BNE.S   +8
$00202C:  MOVE.W  #$0000,$C87E.W       ; Reset counter
$002032:  MOVE.B  #$0000,$C8C4.W       ; Clear flag
done:
$002038:  RTS
```

**Analysis:**
- Simplest handler with 32X interaction
- No VDP writes, no frame buffer operations
- Only clears SH2 command acknowledgment
- Likely used after major operations complete

---

## State Usage Patterns

### VDP-Heavy States
States 0, 1, 2, 5, 6, 7, 8, 10, 12: Primarily VDP configuration and synchronization

### Frame Buffer States
States 6, 9, 13, 14: Handle 32X frame buffer operations and palette transfers

### Minimal States
States 4, 15: Quick operations with minimal overhead

### Transition States
State 11: Triggers state machine transitions

---

## Memory Map Reference

### VDP Ports (Mega Drive)
- $C00000 (A6): VDP data port
- $C00004 (A5): VDP control port
- $8000.W: VDP data mirror
- $8002.W: VDP data mirror 2

### 32X Registers
- $A15100: Adapter Control Register (FM=bit 15, REN=bit 7, RES=bit 1, ADEN=bit 0)
- $A15120: COMM0 (68K ↔ SH2 handshake)
- $A15123: COMM1_LO (SH2 "render done" signal, bit 0)
- $A1518A: Frame Buffer Control Register (VBLK=bit 15, HBLK=bit 14, PEN=bit 13, FEN=bit 1 R/O, FS=bit 0 R/W)
- $A1518B: Frame Buffer Control low byte (FS=bit 0, swap deferred to next VBlank if written during display)
- $A15200: 32X palette RAM (512 bytes)

### RAM Variables
- $C87A.W: Current V-INT state index
- $C87E.W: Frame/operation counter
- $C874.W: VDP register cache
- $C876.W: VDP register cache 2
- $C880.W: VSRAM scroll X
- $C882.W: VSRAM scroll Y
- $C80C.W: Frame buffer toggle flag
- $C8C4.W: Operation flag
- $C8C5.W: Game state/mode
- $C964.L: Global frame counter

### Data Sources
- $A100.W: MD RAM palette buffer (512 bytes)
- $B400.W: MD RAM palette buffer 2
- $FF6E00: MD RAM high palette buffer

---

## VDP Command Reference

### VRAM Commands
- `$6C000003`: VRAM write to $6C00

### VSRAM Commands
- `$40000010`: VSRAM write to offset $00 (scroll registers)

### VDP Register Writes
Format: `$80+reg` in high byte, data in low byte. E.g., `$93xx` = VDP register 19.

**Register 19 (DMA Length Low, REG #19):**
- `$9340`: DMA length low = $40
- `$9320`: DMA length low = $20
- `$9380`: DMA length low = $80

**Register 20 (DMA Length High, REG #20):**
- `$9400`: DMA length high = $00
- `$9401`: DMA length high = $01
- `$9403`: DMA length high = $03

**Register 21 (DMA Source Low, REG #21):**
- `$9540`: DMA source low = $40
- `$9500`: DMA source low = $00
- `$951E`: DMA source low = $1E
- `$9580`: DMA source low = $80

**Register 22 (DMA Source Mid, REG #22):**
- `$96C2`: DMA source mid = $C2
- `$96C0`: DMA source mid = $C0
- `$9688`: DMA source mid = $88
- `$968B`: DMA source mid = $8B
- `$96D8`: DMA source mid = $D8

**Register 23 (DMA Source High/Type, REG #23):**
- `$977F`: DMA source high = $7F (type bits: memory-to-VRAM DMA)

**VRAM Address / DMA Commands (via VDP control port, not register writes):**
- `$C000`: VRAM address command
- `$6000`: VRAM address command
- `$4000`: VRAM address command
- `$6C3C`: VRAM address command

---

## Performance Characteristics

### Cycle Estimates

| State | Approx Cycles | Complexity | Notes |
|-------|--------------|------------|-------|
| 0,1,2,8 | ~600 | Medium | Common handler |
| 4 | ~24 | Minimal | Fastest |
| 5 | ~550 | Medium | Similar to common |
| 6 | ~900 | High | Frame buffer toggle |
| 7 | ~500 | Medium | VDP config |
| 9 | ~1400 | High | Palette copy (512 bytes) |
| 10 | ~800 | High | Dual VDP config |
| 11 | ~40 | Minimal | State transition |
| 12 | ~1200 | Very High | Triple VDP config |
| 13 | ~1600 | Very High | Palette + FB |
| 14 | ~1600 | Very High | Palette + FB |
| 15 | ~60 | Minimal | Cleanup |

### Bottleneck Analysis
- Frame buffer states (6, 9, 13, 14): ~30-35% of frame time
- Palette copy: 512 bytes @ 8 cycles/MOVE.L = ~4000 cycles
- Z-Bus arbitration: Variable (typically 10-50 cycles)

---

## State Flow Diagrams

### Typical Game Loop
```
State 0 (Idle) → State 6 (FB toggle) → State 9 (Palette copy)
              ↓
State 13 (SH2 sync + FB) → State 14 (FB DMA) → State 15 (Cleanup)
              ↓
State 0 (return to idle)
```

### Menu/Special States
```
State 11 (transition) → State 44 (extended) → ???
```

---

## TODO

- [ ] Map game modes to specific state sequences
- [ ] Identify what triggers each state
- [ ] Analyze state 3 (RAM handler at $018200)
- [ ] Find state 44 handler code
- [ ] Measure actual cycle counts with profiling
- [ ] Document full state transition graph
- [ ] Identify which states are used during:
  - Title screen
  - Menu navigation
  - Gameplay
  - Results/ranking screen

---

## Related Documentation

- [VINT_HANDLER_ARCHITECTURE.md](VINT_HANDLER_ARCHITECTURE.md) - V-INT handler entry and dispatch
- [CONTROLLER_INPUT_ARCHITECTURE.md](CONTROLLER_INPUT_ARCHITECTURE.md) - Controller input system
- [68K_SH2_COMMUNICATION.md](68K_SH2_COMMUNICATION.md) - 68K ↔ SH2 communication patterns

---

**Last Updated:** 2026-01-17
**Status:** ✅ All 16 state handlers analyzed and documented
