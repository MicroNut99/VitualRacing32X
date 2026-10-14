# High-Frequency 68K Functions

Documentation for the most frequently called game functions - optimization targets.

## Performance Impact

These functions collectively consume a significant portion of 68K frame budget:
- **68K budget**: ~128,000 cycles/frame @ 7.67 MHz (100% utilization = bottleneck)
- Combined call count: 150+ calls per frame

---

## angle_to_sine ($0070AA) - 29 calls/frame

**Purpose**: Look up sine/cosine values for steering/velocity calculations

**Location**: [code_6200.asm:1073](../sections-mnemonic/code_6200.asm#L1073)

**Algorithm**:
```
1. Load angle delta from object+$5C minus object+$5A
2. Mask to 10 bits (1024-entry table, 360°/1024 ≈ 0.35° resolution)
3. Look up sine from table at $0093A02C
4. Handle negative angles by negating result
5. Store to object+$3E (sine result)
6. Repeat for cosine using table at $0093A42C → object+$3A
7. Calculate derived velocity values
```

**Data Structures**:
- Object+$5A: Base angle
- Object+$5C: Target angle (for sine)
- Object+$5E: Target angle (for cosine)
- Object+$3A: Cosine result
- Object+$3E: Sine result
- Trig tables: 1024 entries × 2 bytes = 2KB each

**Optimization Notes**:
- Called after every steering input update
- Could benefit from CORDIC algorithm or smaller lookup table with interpolation

---

## load_object_params ($0080CC) - 27 calls/frame

**Purpose**: Load object parameters from ROM table

**Location**: [code_6200.asm](../sections-mnemonic/code_6200.asm) (at offset for $0080CC)

**Algorithm**:
```
1. Get object type from structure
2. Look up in parameter table
3. Copy parameters to object structure
```

**Optimization Notes**:
- Table-driven, already efficient
- Could pre-cache frequently used objects

---

## object_frame_timer ($008170) - 22 calls/frame

**Purpose**: Decrement object timers, trigger state changes

**Location**: [code_6200.asm](../sections-mnemonic/code_6200.asm) (at offset for $008170)

**Algorithm**:
```
1. Decrement timer at object+$XX
2. If timer reaches 0, trigger callback or state change
```

**Optimization Notes**:
- Simple countdown loop
- Batch processing could reduce overhead

---

## calc_steering ($006F98) - 19 calls/frame

**Purpose**: Calculate steering angle from input/AI

**Location**: [code_6200.asm:1020](../sections-mnemonic/code_6200.asm) (approximate)

**Algorithm**:
```
1. Read steering input or AI decision
2. Apply steering rate limits
3. Update object angle values
4. Triggers angle_to_sine for velocity update
```

**Optimization Notes**:
- Often followed immediately by obj_position_x/y calls
- Could be combined into single position update

---

## obj_position_y ($007C4E) - 18 calls/frame

**Purpose**: Update Y position from velocity

**Location**: [code_6200.asm](../sections-mnemonic/code_6200.asm)

**Algorithm**:
```
1. Load Y velocity from object+$XX
2. Apply to Y position at object+$YY
3. Handle boundary conditions
```

---

## obj_position_x ($007CD8) - 18 calls/frame

**Purpose**: Update X position from velocity

**Location**: [code_6200.asm](../sections-mnemonic/code_6200.asm)

**Algorithm**: Same as obj_position_y for X axis

---

## obj_velocity_y ($007E7A) - 18 calls/frame

**Purpose**: Apply acceleration to Y velocity

---

## obj_velocity_x ($007F50) - 18 calls/frame

**Purpose**: Apply acceleration to X velocity

---

## Object Structure Offsets

Common offsets used by these functions:

| Offset | Purpose |
|--------|---------|
| $0004 | Speed multiplier |
| $0030 | Y position |
| $0034 | X position |
| $003A | Cosine component |
| $003E | Sine component |
| $0044 | Y velocity |
| $0046 | X velocity |
| $004A | Z velocity? |
| $004E | Y acceleration |
| $0050 | X acceleration |
| $005A | Base angle |
| $005C | Steering angle 1 |
| $005E | Steering angle 2 |
| $006E | Angular velocity |
| $008E | Damping factor |
| $0092 | Object type/flags |
| $0094 | Turn rate |
| $009E | X screen coord |
| $00A0 | Y screen coord? |
| $00A2 | Z screen coord? |

---

## Optimization Strategy

1. **Inline critical paths**: Functions like angle_to_sine are small enough to inline
2. **Batch position updates**: Combine X/Y/velocity updates into single pass
3. **Pre-compute trig**: For AI with predictable angles, cache results
4. **Reduce call overhead**: PC-relative JSR is fast but still costs cycles
5. **SH2 offload**: Position math could run on Slave SH2 during render

---

## Related Files

- [68K_FUNCTION_REFERENCE.md](../../../../analysis/68K_FUNCTION_REFERENCE.md) - Complete function catalog
- [code_6200.asm](../sections-mnemonic/code_6200.asm) - Mnemonic disassembly
- [game_logic_1.asm](game_logic_1.asm) - DC.W format for building
