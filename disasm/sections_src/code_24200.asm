; ============================================================================
; Code Section ($024206-$0261FF)
; Generated from ROM bytes - guaranteed accurate
; Note: $024200-$024205 is part of block_copy_14_short (included in code_22200.asm)
; ============================================================================

        org     $024206

; Literal pool for block_copy_14_short (padding and table base address)
        dc.w    $0000        ; $024206: padding
        ROMDATA $024208,$02420C
; ============================================================================
; block_iterator_short: Byte Block Iterator (26 bytes: $02420C-$024225)
; Iterates through byte array, calls block_copy_14_short for each non-zero element
; ============================================================================
        include "sh2/generated/block_iterator_short.inc"
; Padding between block_iterator_short and vdp_pixel_write_short
        dc.w    $FFFF        ; $024226: sentinel/padding
; ============================================================================
; vdp_pixel_write_short: VDP Pixel Write Loop (76 bytes: $024228-$024273)
; Initializes VDP and processes pixel data with coordinate unpacking
; ============================================================================
        include "sh2/generated/vdp_pixel_write_short.inc"
; ============================================================================
; value_dispatch_short: Value-Based Dispatch (46 bytes: $024274-$0242A1)
; Reads dispatch byte, branches based on 0/0x80/positive/negative
; ============================================================================
        include "sh2/generated/value_dispatch_short.inc"
; Literal pool for value_dispatch_short (addresses and constants)
        ROMDATA $0242A2,$0242AC
; ============================================================================
; negative_fill_short: Negative Value Fill Handler (40 bytes: $0242AC-$0242D3)
; Called when value_dispatch_short dispatches negative value (BF at $024282)
; Fills buffer with incrementing pattern across 28 rows
; ============================================================================
        include "sh2/generated/negative_fill_short.inc"
; Literal pool for negative_fill_short
        dc.w    $2000        ; $0242D4: pattern start high
        dc.w    $0100        ; $0242D6: increment value
        dc.w    $0800        ; $0242D8: row stride
        dc.w    $0000        ; $0242DA: padding
        dc.w    $2400        ; $0242DC: base address high
        dc.w    $0000        ; $0242DE: base address low ($24000000)
; ============================================================================
; fill_decrement_short: Fill with Decrementing Pattern (20 bytes: $0242E0-$0242F3)
; Called when value_dispatch_short dispatches 0x80 value (BT at $02427E)
; Fills buffer with decrementing word pattern
; ============================================================================
        include "sh2/generated/fill_decrement_short.inc"
; Literal pool for fill_decrement_short
        dc.w    $FF00        ; $0242F4: initial pattern
        dc.w    $0100        ; $0242F6: decrement value
        dc.w    $00E0        ; $0242F8: loop count (224)
        dc.w    $0000        ; $0242FA: padding
        dc.w    $2400        ; $0242FC: destination high
        dc.w    $01C0        ; $0242FE: destination low ($240001C0)
; ============================================================================
; memory_clear_short: Memory Clear (34 bytes: $024300-$024321)
; Clears two memory regions by writing zeros
; ============================================================================
        include "sh2/generated/memory_clear_short.inc"
; Literal pool for memory_clear_short
        dc.w    $0000        ; $024322: padding
        dc.w    $0603        ; $024324: region1 end high (0x06033000)
        dc.w    $3000        ; $024326: region1 end low
        dc.w    $0000        ; $024328: region1 count high (0x00001300)
        dc.w    $1300        ; $02432A: region1 count low
        dc.w    $0600        ; $02432C: region2 end high (0x0600EE00)
        dc.w    $EE00        ; $02432E: region2 end low
        dc.w    $0000        ; $024330: region2 count high (0x000004C0)
        dc.w    $04C0        ; $024332: region2 count low
; ============================================================================
; multi_jsr_short: Multi-JSR Coordinator (52 bytes: $024334-$024367)
; Calls 6 subroutines in sequence via JSR
; ============================================================================
        include "sh2/generated/multi_jsr_short.inc"
; Literal pool for multi_jsr_short ($024368-$02438A)
        dc.w    $0600        ; $024368: target 1 high ($06003348)
        dc.w    $3348        ; $02436A: target 1 low
        dc.w    $0600        ; $02436C: target 2 high ($0600441C)
        dc.w    $441C        ; $02436E: target 2 low
        dc.w    $0000        ; $024370: param high ($000004C0)
        dc.w    $04C0        ; $024372: param low
        dc.w    $0600        ; $024374: param high ($0600EDFC)
        dc.w    $EDFC        ; $024376: param low
        dc.w    $0603        ; $024378: param high ($06032FF0)
        dc.w    $2FF0        ; $02437A: param low
        dc.w    $C000        ; $02437C: target 3 high ($C0000022)
        dc.w    $0022        ; $02437E: target 3 low
        dc.w    $0600        ; $024380: target 4 high ($060034EE)
        dc.w    $34EE        ; $024382: target 4 low
        dc.w    $0600        ; $024384: target 5 high ($06004438)
        dc.w    $4438        ; $024386: target 5 low
        dc.w    $0600        ; $024388: target 6 high ($060043E0)
        dc.w    $43E0        ; $02438A: target 6 low
; ============================================================================
; multi_jsr_alt_short: Multi-JSR Coordinator Alt (50 bytes: $02438C-$0243BD)
; Similar to multi_jsr_short with different parameter setup
; ============================================================================
        include "sh2/generated/multi_jsr_alt_short.inc"
; Literal pool for multi_jsr_alt_short ($0243BE-$0243DE)
        dc.w    $0000        ; $0243BE: padding
        dc.w    $0600        ; $0243C0: target 1 high ($06003348)
        dc.w    $3348        ; $0243C2: target 1 low
        dc.w    $0600        ; $0243C4: target 2 high ($0600441C)
        dc.w    $441C        ; $0243C6: target 2 low
        dc.w    $0600        ; $0243C8: param addr high ($0600F200)
        dc.w    $F200        ; $0243CA: param addr low
        dc.w    $0601        ; $0243CC: param high ($06016000)
        dc.w    $6000        ; $0243CE: param low
        dc.w    $C000        ; $0243D0: target 3 high ($C0000160)
        dc.w    $0160        ; $0243D2: target 3 low
        dc.w    $0600        ; $0243D4: target 4 high ($060034EE)
        dc.w    $34EE        ; $0243D6: target 4 low
        dc.w    $0600        ; $0243D8: target 5 high ($06004438)
        dc.w    $4438        ; $0243DA: target 5 low
        dc.w    $0600        ; $0243DC: target 6 high ($060043E0)
        dc.w    $43E0        ; $0243DE: target 6 low
; ============================================================================
; poll_wait_short: Poll Wait Loop (12 bytes: $0243E0-$0243EB)
; Small polling loop waiting for condition
; ============================================================================
        include "sh2/generated/poll_wait_short.inc"
; Literal pool for poll_wait_short ($0243EC)
        dc.w    $2000        ; $0243EC: poll addr high ($20004100)
        dc.w    $4100        ; $0243EE: poll addr low
; ============================================================================
; hw_init_short: Hardware Register Init (28 bytes: $0243F0-$02440B)
; Initializes hardware registers based on condition
; ============================================================================
        include "sh2/generated/hw_init_short.inc"
; Literal pool for hw_init_short ($02440C-$02441A)
        dc.w    $2000        ; $02440C: control reg high ($20004000)
        dc.w    $4000        ; $02440E: control reg low
        dc.w    $2000        ; $024410: status reg high ($20004100)
        dc.w    $4100        ; $024412: status reg low
        dc.w    $2000        ; $024414: output reg 1 high ($20004020)
        dc.w    $4020        ; $024416: output reg 1 low
        dc.w    $2000        ; $024418: output reg 2 high ($20004023)
        dc.w    $4023        ; $02441A: output reg 2 low
; ============================================================================
; poll_zero_short: Poll Until Zero (12 bytes: $02441C-$024427)
; Polling loop that waits until register reads 0, then stores R1
; ============================================================================
        include "sh2/generated/poll_zero_short.inc"
; Literal pool for poll_zero_short ($024428)
        dc.w    $2000        ; $024428: register addr high ($20004024)
        dc.w    $4024        ; $02442A: register addr low
; ============================================================================
; clear_reg_short: Clear Register (8 bytes: $02442C-$024433)
; Simple function that writes 0 to a register
; ============================================================================
        include "sh2/generated/clear_reg_short.inc"
; Literal pool for clear_reg_short ($024434)
        dc.w    $2000        ; $024434: register addr high ($20004024)
        dc.w    $4024        ; $024436: register addr low
; ============================================================================
; poll_zero_alt_short: Poll Until Zero Alternate (12 bytes: $024438-$024443)
; Polling loop that waits until register reads 0
; ============================================================================
        include "sh2/generated/poll_zero_alt_short.inc"
; Literal pool for poll_zero_alt_short ($024444)
        dc.w    $2000        ; $024444: register addr high ($20004024)
        dc.w    $4024        ; $024446: register addr low
; ============================================================================
; struct_init_short: Structure Initialization (34 bytes: $024448-$024469)
; Initializes a structure with values from literal pool
; ============================================================================
        include "sh2/generated/struct_init_short.inc"
; Literal pool for struct_init_short ($02446A-$02447E)
        dc.w    $FF80        ; $02446A: word constant
        dc.w    $2000        ; $02446C: base addr high ($20004000)
        dc.w    $4000        ; $02446E: base addr low
        dc.w    $2000        ; $024470: value high ($20004012)
        dc.w    $4012        ; $024472: value low
        dc.w    $0000        ; $024474: value high ($000044E1)
        dc.w    $44E1        ; $024476: value low
        dc.w    $0000        ; $024478: value high ($00000001)
        dc.w    $0001        ; $02447A: value low
        dc.w    $2000        ; $02447C: control reg high ($20004023)
        dc.w    $4023        ; $02447E: control reg low
; ============================================================================
; poll_branch_short: Poll and Branch with Loop (40 bytes: $024480-$0244A7)
; Complex polling routine with embedded data and secondary loop
; ============================================================================
        include "sh2/generated/poll_branch_short.inc"
; Literal pool for poll_branch_short ($0244A8-$0244B2)
        dc.w    $FF00        ; $0244A8: word constant
        dc.w    $0100        ; $0244AA: word constant
        dc.w    $00E0        ; $0244AC: word constant
        dc.w    $0000        ; $0244AE: padding
        dc.w    $2400        ; $0244B0: buffer addr high ($240001C0)
        dc.w    $01C0        ; $0244B2: buffer addr low
; ============================================================================
; poll_wait_2_short: Poll Wait with Flag Set (24 bytes: $0244B4-$0244CB)
; Polling loop that waits for condition, then sets/clears flag
; ============================================================================
        include "sh2/generated/poll_wait_2_short.inc"
; Literal pool for poll_wait_2_short ($0244CC-$0244D2)
        dc.w    $2000        ; $0244CC: control reg high ($20004100)
        dc.w    $4100        ; $0244CE: control reg low
        dc.w    $0000        ; $0244D0: flag value high ($00008000)
        dc.w    $8000        ; $0244D2: flag value low
; ============================================================================
; poll_copy_short: Poll and Copy (18 bytes: $0244D4-$0244E5)
; Polling loop that waits for condition, then copies value
; ============================================================================
        include "sh2/generated/poll_copy_short.inc"
; Literal pool for poll_copy_short ($0244E6-$0244EE)
        dc.w    $0000        ; $0244E6: padding
        dc.w    $2000        ; $0244E8: control reg high ($20004100)
        dc.w    $4100        ; $0244EA: control reg low
        dc.w    $0000        ; $0244EC: flag value high ($00008000)
        dc.w    $8000        ; $0244EE: flag value low
        ROMDATA $0244F0,$025198
; --- Original cmd $22 handler (3-phase COMM6 handshake, 92 bytes) ---
; Phase 1: recv A1 (dest) via COMM4, COMM6 handshake
; Phase 2: recv D0 (width) / D1 (height) via COMM4/5, COMM6 handshake
; Phase 3: recv A0 (source) via COMM4, COMM6 handshake → block copy
; COMM2 is NEVER written by this protocol — no Slave SH2 spurious dispatch.
        ROMDATA $025198,$026200
