# Controller Input Architecture

## Overview

The controller input system reads Sega Mega Drive 3-button controllers and processes button presses for game use. The code at [disasm/modules/68k/input/controller_read.asm:17EE](disasm/modules/68k/input/controller_read.asm#L17EE) implements the standard Mega Drive controller protocol with button remapping.

## Controller Reading Process

### High-Level Flow

```
Z-Bus Request ($00185E)
  ↓
Wait for Z80 to release bus
  ↓
Set TH = 1 ($40)
  ↓
Read D-pad directions (bits 0-3)
  ↓
Read Start+A (bits 4-5)
  ↓
Set TH = 0 ($00)
  ↓
Read B+C buttons (bits 0-1)
  ↓
Release Z-Bus
  ↓
Button Remapping ($0017EE)
  ↓
Store current + delta states
```

## Memory-Mapped I/O

### Z-Bus Control
- **$00A11100** - Z-Bus request/grant register
  - Write $0100: Request Z80 bus
  - Read bit 0: 0 = granted, 1 = Z80 busy
  - Critical for accessing I/O ports

### Controller Port
- **$00A10003** - Controller port 1 data
- **$00A10005** - Controller port 2 data

Format (3-button controller):
```
TH=1 (first read):
  Bit 7-6: CB (C and B buttons)
  Bit 5-4: 00
  Bit 3-0: UDLR (Up, Down, Left, Right)

TH=0 (second read):
  Bit 7-6: ST (Start button)
  Bit 5-4: SA (Start and A buttons)
  Bit 3-0: 0011 (fixed pattern)
```

## Button Mapping

The code uses a lookup table (pointed to by A3) to remap hardware button bits to game-specific button bits:

### Remapping Table Pattern
From $001760-$00178C, the initialization code sets up:
```
Controller Port Setup:
  $FE82-$FE93: Port configuration
  Pattern: 04 06 01 00 05 0A 09 08 (repeated 2x for 2 players)
```

### Button Bit Assignments

The remapping function at $0017EE maps hardware buttons to D6 register bits:

| Hardware Source | Game Bit | Button |
|-----------------|----------|--------|
| (varies - table driven) | 0 | Button mapped from table[3] |
| (varies - table driven) | 1 | Button mapped from table[2] |
| Bits 2-3 of hardware | 2-3 | D-pad (copied directly) |
| (varies - table driven) | 4 | Button mapped from table[0] |
| (varies - table driven) | 5 | Button mapped from table[5] |
| (varies - table driven) | 6 | Button mapped from table[1] |
| (varies - table driven) | 8 | Button mapped from table[7] |
| (varies - table driven) | 9 | Button mapped from table[6] |
| (varies - table driven) | 10 | Button mapped from table[4] |

## State Tracking

### Input Buffer Structure (A2 points here)

```
Offset  Size  Description
+$00    Word  Previous frame button state
+$02    Word  Current frame button state
+$04    Word  Button delta (newly pressed buttons)
```

### Delta Detection Algorithm

```asm
; At $001852-$00185C
MOVE.W  (A2),D2          ; D2 = previous state
MOVE.W  D6,(A2)+         ; Store current as new previous
EOR.W   D6,D2            ; D2 = changed bits
AND.W   D2,D6            ; D6 = newly pressed (was 0, now 1)
MOVE.W  D6,(A2)+         ; Store delta
RTS
```

This produces:
- **Previous**: Buttons that were pressed last frame
- **Current**: Buttons pressed this frame
- **Delta**: Buttons that transitioned from unpressed to pressed (rising edge)

## Timing Requirements

### Z-Bus Access
```asm
loc_001866:
    BTST    #0,$00A11100    ; Check if Z80 released bus
    BNE.S   loc_001866      ; Loop until granted
```
- Must wait for Z80 to acknowledge bus release
- Failure to wait can cause corrupted reads

### TH Line Timing
The code uses NOP instructions for precise timing:
```asm
MOVE.B  D7,(A1)    ; Set TH high
NOP                ; Wait 1.5μs
NOP                ; Required for controller
NOP                ; to stabilize
NOP                ; before reading
MOVE.B  (A1),D1    ; Read controller state
```

Each NOP = ~0.52μs @ 7.67MHz (68000 @ 7.67 MHz = 4 cycles/NOP)

## Function Reference

### $00185E: Read Controller Port
**Input:**
- A1 = Controller port address ($00A10003 or $00A10005)
- A2 = Destination buffer for button states
- A3 = Button remapping table

**Output:**
- Updates 6 bytes at (A2):
  - Previous state (word)
  - Current state (word)
  - Delta/pressed (word)

**Destroyed:**
- D0, D1, D2, D5, D6, D7

**Process:**
1. Request Z-Bus ($00A11100 = $0100)
2. Wait for grant (poll bit 0)
3. Set TH=1, read D-pad + Start/A
4. Set TH=0, read B/C buttons
5. Combine into final button word
6. Call button remapping routine

### $0017EE: Remap and Store Buttons
**Input:**
- D0 = Raw button state from hardware
- A0 = Pointer to state buffer
- A2 = Pointer to final buffer
- A3 = Button mapping table (8 bytes)

**Output:**
- D6 = Remapped button state
- Updates state buffer with current + delta

**Process:**
1. Calculate button press delta (XOR + AND)
2. Use mapping table to remap bits
3. Store previous/current/delta states

## Configuration Data

### Controller Port Init ($00170C)
Initializes hardware:
```
$FE92 = $00  ; Clear status
$FE93 = $00  ; Clear status

Port 1 setup ($FE82-$FE89):
  04 06 01 00 05 0A 09 08

Port 2 setup ($FE8A-$FE91):
  04 06 01 00 05 0A 09 08
```

These values configure the I/O port direction and data for controller reading.

## System Integration

### Called From
- V-INT handler state machine
- Game logic update routines
- Menu input handlers

### Integration with Game State ($C818)
The V-INT handler at $001764-$001784 checks $C818 bits to select different button mapping tables:
- Bit 0: Changes table offset by $34 bytes
- Bit 1: Changes table offset by $20 bytes

This allows different control schemes for different game modes (menus, gameplay, options).

## Hardware Compatibility

### Supported Controllers
- **3-button controller**: Fully supported (primary target)
- **6-button controller**: May work but not explicitly handled
  - Missing extra button reads
  - May detect as 3-button with incorrect readings

### Known Limitations
- No 6-button detection sequence
- No mouse/light gun support
- Single controller poll per frame
- No de-bouncing logic (assumes clean contacts)

## Performance

- **Worst case**: ~120 cycles for full read
  - Z-Bus wait: Variable (typically <10 cycles)
  - TH toggle + reads: ~40 cycles
  - Remapping: ~70 cycles
- **Percentage of frame**: <0.03% @ 488k cycles/frame
- **Safe to call**: Every frame with negligible overhead

## Usage Example

```asm
; Read controller 1
LEA     $00A10003,A1        ; Controller port 1
LEA     $C970,A2            ; Button state buffer
LEA     button_map_table,A3 ; Mapping table
JSR     $00185E             ; Read controller

; Check if button pressed this frame
MOVE.W  4(A2),D0           ; Load delta (newly pressed)
BTST    #5,D0              ; Check button 5 (example)
BEQ     .no_press
; Handle button press
.no_press:
```

## Related Files

- [input_processing.asm](disasm/modules/68k/input/input_processing.asm) - Button combo detection
- [button_handling.asm](disasm/modules/68k/input/button_handling.asm) - Game-specific button actions
- [state_machine.asm](disasm/modules/68k/input/state_machine.asm) - Input-driven state transitions

## TODO

- [ ] Decode exact button mapping tables
- [ ] Identify button meanings (gas, brake, shift, etc.)
- [ ] Trace all callers to understand usage patterns
- [ ] Check if 6-button mode could be added
- [ ] Document multi-tap support (if any)
