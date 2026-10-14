# Master SH2 Command Handler Reference

**Generated:** 2026-03-16
**Source:** Full disassembly + literal pool decode of all active handlers
**Coverage:** All 7 active Master SH2 command handlers ($00-$06) + Huffman renderer

---

## Dispatch Mechanism

**Dispatch loop:** `$06000460` (SDRAM)
- R8 = `$20004020` (COMM base, cache-through)
- Polls COMM0_HI byte; non-zero = trigger
- Reads COMM0_LO = command index, SHLL2 (×4), loads handler from jump table

**Jump table:** `$06000780` (SDRAM), 16 entries × 4 bytes

| Index | COMM0_LO | Handler | Purpose |
|-------|----------|---------|---------|
| $00 | $00 | `$06000490` | Idle/no-op (ACK only) |
| $01 | $01 | `$060008A0` | Scene init orchestrator (10 subroutines) |
| $02 | $02 | `$06000CFC` | Scene orchestrator (entity loop callers) |
| $03 | $03 | `$06000CC4` | Racing per-frame trigger (buffer clear + done) |
| $04 | $04 | `$060012CC` | Full scene rendering (heaviest, 32 entities) |
| $05 | $05 | `$06001924` | Racing per-frame render (22 entities, visibility cull) |
| $06 | $06 | `$06001A0C` | Bulk DMA copy (track data, 56KB) |
| $07+ | $07-$0F | `$06000490` | Unused → default idle handler |

**COMM0 values used by 68K:**
- Scene init: `$C8A8 = $0102` → COMM0_HI=$01, COMM0_LO=$02
- Race scene init: `$C8A8 = $0103` → COMM0_HI=$01, COMM0_LO=$03
- Per-frame DMA: same value persists in `$C8A8` throughout racing

**Completion handlers:**
- `$060043FC` — Clears COMM0_HI=0, sets COMM1_LO bit 0 ("done"). Used by $00, $03, $06.
- `$060043F0` — Extended: checks adapter FM bit at `$20004000`, then falls through to `$060043FC`. Used by $04, $05.

---

## Handler $00 — Idle/No-Op (`$06000490`)

**Size:** 14 bytes | **ROM offset:** `$020490`

Simplest handler. Calls `$060043FC` (completion) and returns. 7+ jump table entries point here for unused command indices.

```
STS.L   PR,@-R15
MOV.L   $060043FC, R0
JSR     @R0             ; signal done
NOP
LDS.L   @R15+,PR
RTS
```

---

## Handler $01 — Scene Init Orchestrator (`$060008A0`)

**Size:** ~94 bytes + literal pool | **ROM offset:** `$0208A0`

Full initialization pipeline. Called once during scene setup (COMM0_LO=$01). Configures DMAC, initializes rendering contexts, copies Pipeline 1 code to on-chip SRAM, runs entity loop and main coordinator, signals completion.

**Subroutine call sequence:**
| # | Address | Purpose | Key Params |
|---|---------|---------|-----------|
| 1 | `$06004448` | DMAC/FIFO setup | R1=`$0600C000` (destination) |
| 2 | `$060044F6` | PWM audio FIFO fill | R1=$3000, R2=$009F, R3=$00C0 |
| 3 | `$06004480` | Wait DMA complete + cache flush | — |
| 4 | `$06000BBC` | *Data pointer* (vertex normal table, stored to context[$10]) | — |
| 5 | `$06000DC8` | Entity transform pipeline setup | 9 sub-calls, 36 entities |
| 6 | `$0600252C` | SRAM copy (1748B → `$C0000000`) | — |
| 7 | `$060022BC` | SRAM rendering context init | Viewport, function ptrs |
| 8 | `$060024DC` | Entity loop (Pipeline 1) | R7=1, R13=`$0600CA60`, R14=`$0600C128` |
| 9 | `$060032D4` | Display list/viewport init | 14 longwords, 256 entries |
| 10 | `$06004334` | Scene finalize | COMM2 handshake, SRAM code call |

**Epilogue:** Clears COMM0_HI, sets COMM1_LO bit 0.

---

## Handler $02 — Scene Orchestrator (`$06000CFC`)

**Size:** ~100 bytes | **ROM offset:** `$020CFC`

Contains BSR calls to entity loop callers at `$0600115C`, `$06000EB4`, `$060010AC`. Has an extensive subroutine chain documented in the oracle index. Dispatches entity rendering via function pointers loaded from literal pools.

*(Pre-existing documentation in oracle/index.md §SH2 Dispatch Architecture)*

---

## Handler $03 — Racing Per-Frame Trigger (`$06000CC4`)

**Size:** 32 bytes + literal pool | **ROM offset:** `$020CC4`

Lightweight handler for per-frame racing. Does NOT render — just prepares buffers.

**Sequence:**
1. JSR `$06004300` — Clear ~82KB of render buffers (two regions: `$06020000`-`$06033000` and `$0600DA00`-`$0600EE00`)
2. Write state flags: `$0600F208` = 1, `$0600F20A` = 1
3. Read COMM1_HI; if non-zero, JSR `$06004664` (track data loader)
4. JMP `$060043FC` (completion, delay slot restores PR)

**COMM usage:** Reads COMM1_HI for track selection flag. Writes COMM0_HI=0 and COMM1_LO bit 0 via completion handler.

---

## Handler $04 — Full Scene Rendering (`$060012CC`)

**Size:** ~120 bytes + 4 local BSRs (~800 bytes total) | **ROM offset:** `$0212CC`

Heaviest handler. Two-pass entity setup processing 32 entities from `$0600C800` data structure.

**Subroutine call sequence:**
| # | Address | Purpose |
|---|---------|---------|
| 1 | `$06004448` | DMAC/FIFO setup (R1=`$0600C000`) |
| 2 | `$060044F6` | PWM audio FIFO fill |
| 3 | `$06004480` | Wait DMA + cache flush |
| 4 | `$06004274` | Unknown setup |
| 5 | `$0600441C` | COMM2 handshake (R1=6) — sync with 68K |
| 6 | BSR local | Pass 1: entity geometry table setup |
| 7 | BSR local | Pass 2: entity geometry table setup |
| 8 | `$06004274` | Setup (second call) |
| 9 | `$0600441C` | COMM2 handshake (R1=3) |
| 10 | BSR local | On-chip SRAM sort/draw via `$C000008A` and `$C00000E8` |
| 11 | BSR local | Entity loop (32 entries from `$0600C800`, stride $10) |
| 12 | `$0600252C` | SRAM copy |
| 13 | JMP `$060043F0` | Extended completion |

**Key data structure:** `$0600C800`, 32 entries × 16 bytes. Byte flag at offset +0 determines visibility.

**Sync primitives:** Uses `$0600441C` (COMM2 handshake) twice — writes R1=6 before geometry pass, R1=3 before render pass.

---

## Handler $05 — Racing Per-Frame Render (`$06001924`)

**Size:** ~120 bytes + BSR subs | **ROM offset:** `$021924`

Active rendering handler for racing. Lighter than $04 — processes 22 entities with visibility culling.

**Subroutine call sequence:**
| # | Address | Purpose |
|---|---------|---------|
| 1 | `$06004448` | DMAC/FIFO setup (cache-through `$2600C000`) |
| 2 | `$060044F6` | PWM audio |
| 3 | `$06004480` | Wait DMA + cache flush |
| 4 | `$06000DC8` | Entity transform pipeline (36 entities, 9 sub-calls) |
| 5 | Visibility check | Read `$0600C0C8`/`$0600C0CA`; skip if $FFFF or equal |
| 6 | `$0600252C` | SRAM copy |
| 7 | `$060022BC` | SRAM rendering context init |
| 8 | `$060024DC` | Entity loop (Pipeline 1) |
| 9 | `$060032D4` | Display list/viewport init |
| 10 | BSR | Copy visibility range to on-chip SRAM `$C0000714`/`$C0000718` |
| 11 | `$06004334` | Scene finalize |
| 12 | `$06004060` | Secondary entity loop (6 entities) |
| 13 | JMP `$060043F0` | Extended completion |

**Visibility culling:** Reads 2 words from `$0600C0C8`/`$0600C0CA` (camera view range?). If either is $FFFF or they're equal, skips the heavy render path (steps 6-11). This is the game's built-in LOD/range culling.

---

## Handler $06 — Bulk DMA Copy (`$06001A0C`)

**Size:** ~32 bytes + sub-function | **ROM offset:** `$021A0C`

Loads track/texture data from ROM into SDRAM during scene transitions.

**Sequence:**
1. R3 = `$01800000` (source stride/config), R4 = `$02260000` (ROM source), R5 = `$0000DB90` (56,208 bytes)
2. JSR `$06004228` — PWM audio output (feeds audio during load)
3. JMP `$060043FC` — Completion

The actual bulk copy is handled by `$06004228` which also manages PWM audio output during the transfer — audio keeps playing while track data loads.

---

## Huffman Renderer (`$06004AD0` — Slave Dispatch)

**Size:** ~500 bytes (decoder + table builder + output handlers) | **ROM offset:** `$024AD0`

**NOT a Master SH2 handler** — dispatched by the Slave SH2. Decompresses Huffman-encoded scene geometry data to SDRAM `$0600C000`.

**Data flow:**
1. 68K writes compressed data pointer to COMM4 (`$20004028`)
2. Slave reads pointer into R9 (bitstream cursor)
3. Clears COMM6 (ACK to 68K)
4. Parses Huffman header: bit 31 selects mode (straight store vs XOR/delta), bits 18-30 = entry count
5. Builds 256-entry fast-lookup table at `$06003000`
6. Decodes bitstream: 8-bit table lookup, 4-bit symbol accumulation, packs 8 nibbles per longword
7. Output to `$0600C000` via selected handler (straight or XOR/delta)
8. Signals completion via `$060043FC`

**Output format:** Sequential longwords at `$0600C000`, each containing 8 packed 4-bit values. Up to 512 longwords (2KB).

**Two decode modes:**
- **Straight store** (`$06004C48`): Direct longword write
- **XOR/delta store** (`$06004C5C`): Each output XOR'd with previous — compresses similar consecutive data

**Correction:** Oracle previously stated this function reads from `$0600C800`. That is **incorrect** — it reads from COMM4 (arbitrary address) and writes to `$0600C000`.

---

## Shared Subroutine Reference

| Address | Size | Name | Purpose | Callers |
|---------|------|------|---------|---------|
| `$06004448` | 34B | dmac_fifo_setup | Configure DMAC ch0: FIFO→SDRAM, set ACK bit 1 | $01, $04, $05 |
| `$060044F6` | 42B | pwm_fifo_fill | Feed 192 PWM audio samples | $01, $04, $05 |
| `$06004480` | 14B | wait_dma_flush_cache | Wait DMAC done, purge+enable cache | $01, $04, $05 |
| `$06000DC8` | 128B | entity_transform_pipeline | 9 sub-calls, 36 entities through transforms | $01, $05 |
| `$0600252C` | ~20B | sram_copy_1748 | Copy 1748B rendering code to `$C0000000` | $01, $04, $05 |
| `$060022BC` | 240B | sram_context_init | Init on-chip SRAM `$C0000700` with viewport + func ptrs | $01, $05 |
| `$060024DC` | ~40B | entity_loop | Pipeline 1 entity rendering dispatcher | $01, $04, $05 |
| `$060032D4` | 54B | display_list_init | Viewport params + 256 display list entries | $01, $05 |
| `$06004334` | 52B | scene_finalize | COMM2 sync, SRAM code call, FB swap ctrl | $01, $05 |
| `$06004300` | 36B | buffer_clear_82k | Zero `$06020000`-`$06033000` + `$0600DA00`-`$0600EE00` | $03 |
| `$06004664` | 48B | track_data_loader | Load track data from ROM by index (1-4) | $03 (conditional) |
| `$0600441C` | 12B | comm2_handshake | Spin on COMM2_HI=0, write R1 | $04, $06004334 |
| `$06004228` | 76B | pwm_audio_output | Feed stereo samples to PWM hardware | $06 |
| `$060043FC` | 16B | completion_signal | Clear COMM0_HI, set COMM1_LO bit 0 | $00, $03, $06, Huffman |
| `$060043F0` | 12B | completion_extended | Check FM bit, then → `$060043FC` | $04, $05 |
| `$06000BBC` | data | vertex_normal_table | 8 cube corners at ±512 (bounding box data) | $01 (ptr stored) |

---

## SDRAM Data Structures

| Address | Size | Purpose | Handlers |
|---------|------|---------|----------|
| `$0600C000` | 2KB | Huffman decoded entity data (output buffer) | Huffman renderer, $01, $04 |
| `$0600C100`-`$0600C7xx` | ~1.7KB | Entity descriptor arrays (R14 base) | $01 ($06000DC8), $05 |
| `$0600C800` | 512B | Entity visibility table (32 × 16B, byte flags) | $04 |
| `$0600CA00`-`$0600D9xx` | ~4KB | Entity output buffers (R13 base) | $01 ($06000DC8) |
| `$0600F208` | 2B | Render state flag | $03 |
| `$0600F20A` | 2B | Render state flag | $03 |
| `$06003000` | 512B | Huffman lookup table (rebuilt per invocation) | Huffman renderer |
| `$06018000`+ | varies | Display list buffer | $060032D4 |

---

## Inter-CPU Synchronization

| Mechanism | Address | Direction | Purpose |
|-----------|---------|-----------|---------|
| COMM0_HI | `$20004020` | 68K→SH2 | Trigger flag (non-zero = command pending) |
| COMM0_LO | `$20004021` | 68K→SH2 | Command index (dispatch via jump table) |
| COMM1_LO bit 0 | `$20004023` | SH2→68K | "Done" signal (set by completion handler) |
| COMM1_LO bit 1 | `$20004023` | SH2→68K | "ACK/FIFO ready" (set by `$06004448`) |
| COMM2_HI | `$20004024` | Bidirectional | Frame sync barrier (`$0600441C` handshake) |
| COMM4 | `$20004028` | 68K→SH2 | Scene data pointer (Huffman renderer input) |
| COMM6 | `$2000402C` | SH2→68K | Cleared by Huffman renderer as ACK |
| COMM7 | `$2000402E` | 68K→Slave | Doorbell for async cmd $27 (B-003) |
