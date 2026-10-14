; ============================================================================
; Code Section ($00E200-$0101FF)
; Translated assembly with byte-accurate dc.w verification
; ============================================================================

        include "disasm/modules/shared/vasm_macros.asm"

; All hardware register equates in modules/shared/definitions.asm (global)

        org     $00E200

; ============================================================================
; Counter increment with modulo ($00E200-$00E20A)
; Increments D0, wraps at 4, loops D3 times
; ============================================================================
CounterIncrementMod4:
        ADDQ.W  #1,D0           ; $00E200: Increment counter
        ANDI.W  #$0003,D0       ; $00E202: Modulo 4 (wrap 0-3)
        dc.w    $51CB,$FFC2     ; $00E206: DBRA D3,$E1CA (loop in code_c200)
        RTS                     ; $00E20A

; ============================================================================
; Data tables ($00E20C-$00E22A)
; ============================================================================
        ROMDATA $00E20C,$00E22C

; ============================================================================
; sh2_graphics_cmd ($00E22C) - Build Graphics Command Data
; ============================================================================
; Called by: 14 locations per frame (sprite/graphics setup)
; Parameters:
;   A0 = Source data pointer
;   D0 = Flags/mode value
;   D1 = Initial offset
;   D2 = Row count parameter
;   D3 = Column count parameter
;   D4 = Vertical loop count
; Returns:
;   A0 = Restored to original value (via A1)
;   D6 = Last computed sprite index
;
; This function builds sprite command data for the SH2 to process.
; It calculates sprite indices based on input parameters and writes
; them to a buffer with $80-byte row stride.
;
; Algorithm:
;   1. Calculate base sprite index from D0/D1/D2
;   2. Build upper section (loop D4-3 times)
;   3. Build center row
;   4. Build lower section with mirrored indices
;   5. Restore A0 and return
; ============================================================================
sh2_graphics_cmd:
; Save original pointer
        movea.l a0,a1                           ; $00E22C: $2248       - Save A0 in A1

; Calculate table offset: D1 = D1*2 + D2*128 + base
        LSL.W   #1,D1                           ; $00E22E: D1 *= 2
        LSL.W   #7,D2                           ; $00E230: D2 *= 128
        add.w   d2,d1                           ; $00E232: D1 += D2
        lea     (a0,d1.w),a0                    ; $00E234: A0 += D1 (indexed)

; Build sprite base index from D0
        andi.w  #$0003,d0                       ; $00E238: Keep low 2 bits
        LSL.W   #8,D0                           ; $00E23C: D0 *= 256
        lsl.w   #5,d0                           ; $00E23E: D0 *= 32 (total *8192)
        addi.w  #$0100,d0                       ; $00E240: $0640 $0100 - Add base offset
        bclr    #11,d0                          ; $00E244: $0880 $000B - Clear bit 11
        bclr    #12,d0                          ; $00E248: $0880 $000C - Clear bit 12

; Initialize counters
        moveq   #0,d1                           ; $00E24C: $7200       - D1 = 0
        move.w  #$0006,d2                       ; $00E24E: $343C $0006 - D2 = 6
        add.w   d0,d2                           ; $00E252: $D440       - D2 += base index
        move.w  d2,(a0)                         ; $00E254: $3082       - Store first index
        adda.l  #$00000080,a0                   ; $00E256: $D1FC $0000 $0080 - Next row (+128)

; Build upper section rows
        move.w  #$0001,d2                       ; $00E25C: $343C $0001 - D2 = 1 (index offset)
        move.w  d4,d5                           ; $00E260: $3A04       - D5 = row count
        subq.w  #3,d5                           ; $00E262: $5745       - D5 -= 3 (loop count)

.upper_loop:
        jsr     sh2_sprite_calc(pc)             ; $00E264: JSR (d16,PC) sh2_sprite_calc
        move.w  d6,(a0)                         ; $00E268: $3086       - Store index
        adda.l  #$00000080,a0                   ; $00E26A: $D1FC $0000 $0080 - Next row
        dbra    d5,.upper_loop                  ; $00E270: $51CD $FFF2 - Loop

; Center row - special index
        move.w  #$0007,d2                       ; $00E274: $343C $0007 - D2 = 7
        jsr     sh2_sprite_calc(pc)             ; $00E278: JSR (d16,PC) sh2_sprite_calc
        move.w  d6,(a0)+                        ; $00E27C: $30C6       - Store and advance

; Build horizontal strip
        move.w  #$0003,d2                       ; $00E27E: $343C $0003 - D2 = 3
        move.w  d3,d5                           ; $00E282: $3A03       - D5 = column count
        subq.w  #3,d5                           ; $00E284: $5745       - D5 -= 3

.horiz_loop:
        jsr     sh2_sprite_calc(pc)             ; $00E286: JSR (d16,PC) sh2_sprite_calc
        move.w  d6,(a0)+                        ; $00E28A: $30C6       - Store and advance
        dbra    d5,.horiz_loop                  ; $00E28C: $51CD $FFF8 - Loop

; Set mirror bits for lower section
        bset    #11,d0                          ; $00E290: $08C0 $000B - Set bit 11
        bset    #12,d0                          ; $00E294: $08C0 $000C - Set bit 12

; End of center row
        move.w  #$0005,d2                       ; $00E298: $343C $0005 - D2 = 5
        jsr     sh2_sprite_calc(pc)             ; $00E29C: JSR (d16,PC) sh2_sprite_calc
        move.w  d6,(a0)                         ; $00E2A0: $3086       - Store index
        suba.l  #$00000080,a0                   ; $00E2A2: $91FC $0000 $0080 - Previous row

; Build lower section rows (going backwards)
        move.w  #$0001,d2                       ; $00E2A8: $343C $0001 - D2 = 1
        move.w  d4,d5                           ; $00E2AC: $3A04       - D5 = row count
        subq.w  #3,d5                           ; $00E2AE: $5745       - D5 -= 3

.lower_loop:
        jsr     sh2_sprite_calc(pc)             ; $00E2B0: JSR (d16,PC) sh2_sprite_calc
        move.w  d6,(a0)                         ; $00E2B4: $3086       - Store
        suba.l  #$00000080,a0                   ; $00E2B6: $91FC $0000 $0080 - Previous row
        dbra    d5,.lower_loop                  ; $00E2BC: $51CD $FFF2 - Loop

; Final corner index
        move.w  #$0007,d2                       ; $00E2C0: $343C $0007 - D2 = 7
        jsr     sh2_sprite_calc(pc)             ; $00E2C4: JSR (d16,PC) sh2_sprite_calc
        move.w  d6,(a0)                         ; $00E2C8: $3086       - Store
        subq.l  #2,a0                           ; $00E2CA: $5588       - Back 2 bytes

; Build final horizontal strip (backwards)
        move.w  #$0003,d2                       ; $00E2CC: $343C $0003 - D2 = 3
        move.w  d3,d5                           ; $00E2D0: $3A03       - D5 = column count
        subq.w  #3,d5                           ; $00E2D2: $5745       - D5 -= 3

.final_loop:
        jsr     sh2_sprite_calc(pc)             ; $00E2D4: JSR (d16,PC) sh2_sprite_calc
        move.w  d6,(a0)                         ; $00E2D8: $3086       - Store
        subq.l  #2,a0                           ; $00E2DA: $5588       - Back 2 bytes
        dbra    d5,.final_loop                  ; $00E2DC: $51CD $FFF6 - Loop

; Restore original pointer and return
        movea.l a1,a0                           ; $00E2E0: $2049       - Restore A0
        rts                                     ; $00E2E2: $4E75
; ============================================================================
; sh2_sprite_calc ($00E2E4) - Calculate Sprite Index
; ============================================================================
; Called by: sh2_graphics_cmd (internal helper)
; Parameters:
;   D0 = Base sprite index
;   D1 = Offset accumulator
;   D2 = Index offset to add
; Returns:
;   D6 = Calculated sprite index (D0 + D1 + D2)
;   D1 = Bit 0 toggled (alternating pattern)
; ============================================================================
sh2_sprite_calc:
        move.w  d2,d6                           ; $00E2E4: $3C02       - D6 = D2
        add.w   d0,d6                           ; $00E2E6: $DC40       - D6 += D0 (base)
        add.w   d1,d6                           ; $00E2E8: $DC41       - D6 += D1 (offset)
        bchg    #0,d1                           ; $00E2EA: $0841 $0000 - Toggle D1 bit 0
        rts                                     ; $00E2EE: $4E75
; ============================================================================
; sh2_load_data ($00E2F0) - Transfer Data to VDP
; ============================================================================
; Called by: Graphics initialization, tile loading
; Parameters:
;   A0 = Source data pointer
;   A5 = VDP control port ($C00004)
;   A6 = VDP data port ($C00000)
; Returns:
;   Data copied to VDP, counter in D0
;
; This function sets up VDP VRAM write and copies tile data.
; Writes 32 longs (128 bytes) per row, then pads with zeros.
; Total: 28 rows × 64 longs = 1792 longs = 7168 bytes
; ============================================================================
sh2_load_data:
        move.l  #$60000002,(a5)                 ; $00E2F0: VDP VRAM write setup command
        moveq   #$1B,d0                         ; $00E2F6: $701B               - D0 = 27 (28 rows)

.row_loop:
        move.w  #$001F,d1                       ; $00E2F8: $323C $001F         - D1 = 31 (32 longs)
.copy_loop:
        move.l  (a0)+,(a6)                      ; $00E2FC: Copy long to VDP data port
        dbra    d1,.copy_loop                   ; $00E2FE: $51C9 $FFFC         - Loop 32 times

        move.w  #$001F,d1                       ; $00E302: $323C $001F         - D1 = 31
.zero_loop:
        move.l  #$00000000,(a6)                 ; $00E306: Zero-fill VDP data
        dbra    d1,.zero_loop                   ; $00E30C: $51C9 $FFF8         - Loop 32 times

        dbra    d0,.row_loop                    ; $00E310: $51C8 $FFE6         - Loop 28 rows
        rts                                     ; $00E314: $4E75

; ============================================================================
; sh2_send_cmd_wait ($00E316) - Command $25, original game code
; ============================================================================
; VR32X V8: upstream's single-shot version (B-005) replaced; this is the
; original 2-phase handshake again (scene init only, 8 call sites).
; Parameters:
;   A0 = 68K data pointer (converted to SH2 address space)
;   A1 = Secondary data pointer (sent in phase 2 by sh2_wait_response)
; Clobbers: A0 (adds $02000000)
; ============================================================================
sh2_send_cmd_wait:
.wait_ready:
        tst.b   COMM0_HI                        ; $00E316: previous command done?
        bne.s   .wait_ready
        adda.l  #SH2_ADDR_OFFSET,a0             ; $00E31E: A0 += $02000000
        move.l  a0,($00A15128).l                ; $00E324: data pointer
        move.w  #$0101,($00A1512C).l            ; $00E32A: ready
        move.b  #$25,COMM0_LO                   ; $00E332: command $25
        move.b  #$01,COMM0_HI                   ; $00E33A: trigger
        ; falls through

; ============================================================================
; sh2_wait_response ($00E342) - wait for the Master, then send A1
; ============================================================================
sh2_wait_response:
.wait_ack:
        tst.b   ($00A1512C).l                   ; $00E342: Master took it?
        bne.s   .wait_ack
        move.l  a1,($00A15128).l                ; $00E34A: secondary pointer
        move.w  #$0101,($00A1512C).l            ; $00E350: ready
        rts                                     ; $00E358

; ============================================================================
; sh2_send_cmd ($00E35A) - Direct Command Send (cmd $22), original game code
; ============================================================================
; VR32X V7: the original 3-phase handshake is back. Upstream's single-shot
; version (B-004) and async sh2_cmd_27 (B-003) both put parameters in
; $A15124-$A1512D at the same time; together they slowed the car select and
; the menu fades to about a quarter speed (see KNOWN_ISSUES.md).
; Called by: text_render, various graphics functions (14 call sites)
; Parameters:
;   A0 = Data pointer (written to $A15128 in phase 3)
;   A1 = Secondary pointer (written to $A15128 in phase 1)
;   D0 = Parameter 1 (width/count, $A15128 in phase 2)
;   D1 = Parameter 2 (height/type, $A1512A in phase 2)
; Clobbers: Nothing
; Each phase waits until the Master clears $A1512C.
; ============================================================================
sh2_send_cmd:
.wait_ready:
        tst.b   COMM0_HI                        ; $00E35A: previous command done?
        bne.s   .wait_ready
        move.l  a1,($00A15128).l                ; $00E362: secondary pointer
        move.w  #$0101,($00A1512C).l            ; $00E368: ready
        move.b  #$22,COMM0_LO                   ; $00E370: command $22
        move.b  #$01,COMM0_HI                   ; $00E378: trigger
.wait_phase1:
        tst.b   ($00A1512C).l                   ; $00E380: Master took it?
        bne.s   .wait_phase1
        move.w  d0,($00A15128).l                ; $00E388: D0
        move.w  d1,($00A1512A).l                ; $00E38E: D1
        move.w  #$0101,($00A1512C).l            ; $00E394: ready
.wait_phase2:
        tst.b   ($00A1512C).l                   ; $00E39C
        bne.s   .wait_phase2
        move.l  a0,($00A15128).l                ; $00E3A4: data pointer
        move.w  #$0101,($00A1512C).l            ; $00E3AA: ready
        rts                                     ; $00E3B2

; ============================================================================
; sh2_cmd_27 ($00E3B4) - Command $27 through the Master, original game code
; ============================================================================
; Called by: menu highlights, HUD, sprite rendering (38 call sites)
; Parameters:
;   A0 = Data pointer
;   D0 = Parameter 1, D1 = Parameter 2, D2 = Parameter 3
; Clobbers: Nothing
; Phase 1: pointer + command $27, wait. Phase 2: D0/D1, wait.
; Phase 3: D2, return (the Master finishes on its own).
; ============================================================================
sh2_cmd_27:
        move.l  a0,($00A15128).l                ; $00E3B4: pointer
        move.w  #$0101,($00A1512C).l            ; $00E3BA: ready
        move.b  #$27,COMM0_LO                   ; $00E3C2: command $27
        move.b  #$01,COMM0_HI                   ; $00E3CA: trigger
.cmd27_wait_phase1:
        tst.b   ($00A1512C).l                   ; $00E3D2
        bne.s   .cmd27_wait_phase1
        move.w  d0,($00A15128).l                ; $00E3DA: D0
        move.w  d1,($00A1512A).l                ; $00E3E0: D1
        move.w  #$0101,($00A1512C).l            ; $00E3E6: ready
.cmd27_wait_phase2:
        tst.b   ($00A1512C).l                   ; $00E3EE
        bne.s   .cmd27_wait_phase2
        move.w  d2,($00A15128).l                ; $00E3F6: D2
        move.w  #$0101,($00A1512C).l            ; $00E3FC: ready
        rts                                     ; $00E404

; ============================================================================
; sh2_cmd_2F ($00E406) - Extended Command with 4 Parameters
; ============================================================================
; Purpose: Sends command $2F with data pointer and 4 parameters (D0-D3)
; Called by: Complex graphics operations
; Parameters:
;   A0 = Data pointer (68K address, written directly to COMM4)
;   D0 = Parameter 1 (written as COMM4 in phase 2)
;   D1 = Parameter 2 (written as COMM5 in phase 2)
;   D2 = Parameter 3 (written as COMM4 in phase 3)
;   D3 = Parameter 4 (written as COMM5 in phase 3)
; Clobbers: Nothing
; Preserves: D0-D7, A0-A6 (all registers preserved)
;
; BLOCKING: Contains THREE busy-wait loops
; Similar to sh2_cmd_27 but with an additional parameter phase
;
; Protocol:
;   Phase 1: Wait for ready, send A0 pointer, command $2F, wait for ack
;   Phase 2: Send D0/D1, wait for ack
;   Phase 3: Send D2/D3, return (SH2 processes async)
; ============================================================================
sh2_cmd_2F:
; Phase 1: Wait for SH2 ready, then send pointer and command
.cmd2F_wait_ready:
        tst.b   COMM0_HI                        ; $00E406: $4A39 $00A1 $5120 - Test command flag
        bne.s   .cmd2F_wait_ready               ; $00E40C: $66F8             - Loop until ready
        move.l  a0,COMM4                        ; $00E40E: $23C8 $00A1 $5128 - Write pointer
        move.w  #HANDSHAKE_READY,COMM6          ; $00E414: $33FC $0101 $00A1 $512C - Signal ready
        move.b  #CMD_EXTENDED,COMM0_LO          ; $00E41C: $13FC $002F $00A1 $5121 - Command $2F
        move.b  #$01,COMM0_HI                   ; $00E424: $13FC $0001 $00A1 $5120 - Trigger

; Phase 2: Wait for ack, send D0/D1
.cmd2F_wait_phase1:
        tst.b   COMM6                           ; $00E42C: $4A39 $00A1 $512C - Check handshake
        bne.s   .cmd2F_wait_phase1              ; $00E432: $66F8             - Loop until clear
        move.w  d0,COMM4                        ; $00E434: $33C0 $00A1 $5128 - Write D0
        move.w  d1,COMM5                        ; $00E43A: $33C1 $00A1 $512A - Write D1
        move.w  #HANDSHAKE_READY,COMM6          ; $00E440: $33FC $0101 $00A1 $512C - Signal ready

; Phase 3: Wait for ack, send D2/D3 (no final wait - SH2 processes async)
.cmd2F_wait_phase2:
        tst.b   COMM6                           ; $00E448: $4A39 $00A1 $512C - Check handshake
        bne.s   .cmd2F_wait_phase2              ; $00E44E: $66F8             - Loop until clear
        move.w  d2,COMM4                        ; $00E450: $33C2 $00A1 $5128 - Write D2
        move.w  d3,COMM5                        ; $00E456: $33C3 $00A1 $512A - Write D3
        move.w  #HANDSHAKE_READY,COMM6          ; $00E45C: Signal ready
        rts                                     ; $00E464: Return

; ============================================================================
; Byte processing loop ($00E466-$00E49E)
; ============================================================================
; Reads bytes from (A2), extracts nibbles, calls helper for each
; Parameters: A1 = destination pointer, A2 = source data
; ============================================================================
ByteProcessLoop:
        MOVE.B  (A2)+,D1                        ; $00E466: Read byte
        ANDI.W  #$000F,D1                       ; $00E468: Mask low nibble
        BSR.W   DigitToASCII                    ; $00E46C: Process (+$4E)
        ADDQ.L  #8,A1                           ; $00E470: Advance pointer
        MOVE.W  #$000A,D1                       ; $00E472: D1 = 10
        BSR.W   DigitToASCII                    ; $00E476: Process (+$44)
        ADDQ.L  #8,A1                           ; $00E47A: Advance pointer
        MOVE.B  (A2)+,D2                        ; $00E47C: Read next byte
        BSR.W   $00E4A0                         ; $00E47E: Bit manip helper (+$20)
        MOVE.W  #$000B,D1                       ; $00E482: D1 = 11
        BSR.W   DigitToASCII                    ; $00E486: Process (+$34)
        ADDQ.L  #8,A1                           ; $00E48A: Advance pointer
        MOVE.B  (A2)+,D1                        ; $00E48C: Read byte
        ANDI.W  #$000F,D1                       ; $00E48E: Mask low nibble
        BSR.W   DigitToASCII                    ; $00E492: Process (+$28)
        ADDQ.L  #8,A1                           ; $00E496: Advance pointer
        MOVE.B  (A2)+,D2                        ; $00E498: Read next byte
        BSR.W   $00E4A0                         ; $00E49A: Bit manip helper (+$4)
        RTS                                     ; $00E49E

; ============================================================================
; Helper function ($00E4A0-$00E4BA)
; ============================================================================
; Bit manipulation and conditional branching helper
; Parameters: D2 = input value, A1 = pointer
; ============================================================================
        move.b  d2,d1                           ; $00E4A0: $1202       - D1 = D2 (byte)
        lsr.b   #4,d1                           ; $00E4A2: $E809       - D1 >>= 4 (high nibble)
        andi.w  #$000F,d1                       ; $00E4A4: $0241 $000F - Mask to 4 bits
        bsr.w   DigitToASCII                    ; $00E4A8: BSR.W DigitToASCII
        addq.l  #8,a1                           ; $00E4AC: $5089       - A1 += 8
        move.w  d2,d1                           ; $00E4AE: $3202       - D1 = D2 (word)
        andi.w  #$000F,d1                       ; $00E4B0: $0241 $000F - Mask to 4 bits (low nibble)
        bsr.w   DigitToASCII                    ; $00E4B4: BSR.W DigitToASCII
        addq.l  #8,a1                           ; $00E4B8: $5089       - A1 += 8
        rts                                     ; $00E4BA: $4E75

; ============================================================================
; Digit conversion helper ($00E4BC-$00E4D8)
; ============================================================================
; Converts digit to ASCII and stores it
; Parameters: D1 = digit value (0-15), A1 = destination pointer
; Uses: D0, A0
; ============================================================================
DigitToASCII:
        lsl.w   #6,d1                           ; $00E4BC: D1 <<= 6 (multiply by 64)
        move.w  d1,d0                           ; $00E4BE: D0 = D1
        lsl.w   #1,d1                           ; $00E4C0: D1 <<= 1 (D1 *= 128)
        add.w   d0,d1                           ; $00E4C2: D1 += D0 (D1 *= 192)
        movea.l #$0603DA00,a0                   ; $00E4C4: Load table base
        add.w   d1,a0                           ; $00E4CA: A0 += D1 (offset)
        move.w  #$000C,d0                       ; $00E4CC: D0 = 12 (width)
        move.w  #$0010,d1                       ; $00E4D0: D1 = 16 (height)
        jsr     sh2_send_cmd(pc)                ; $00E4D4: JSR (d16,PC) sh2_send_cmd
        rts                                     ; $00E4D8

; ============================================================================
; sh2_cmd_21 ($00E4DA-$00E52A) - Command $21
; ============================================================================
; Purpose: Sends command $21 with secondary pointer and 2 parameters
; Called by: Graphics/rendering functions
; Parameters:
;   A0 = Data pointer (written as COMM4 in phase 3)
;   A1 = Secondary pointer (written as COMM4 in phase 1)
;   D0 = Parameter 1 (written as COMM4 in phase 2)
;   D1 = Parameter 2 (written as COMM5 in phase 2)
; Clobbers: Nothing
; Preserves: D0-D7, A0-A6 (all registers preserved)
;
; BLOCKING: Contains TWO busy-wait loops
; Similar protocol to sh2_cmd_27
; ============================================================================
sh2_cmd_21:
; Phase 1: Send secondary pointer and command
        move.l  a1,COMM4                        ; $00E4DA: $23C9 $00A1 $5128 - Write A1
        move.w  #HANDSHAKE_READY,COMM6          ; $00E4E0: $33FC $0101 $00A1 $512C - Signal ready
        move.b  #CMD_21,COMM0_LO                ; $00E4E8: $13FC $0021 $00A1 $5121 - Command $21
        move.b  #$01,COMM0_HI                   ; $00E4F0: $13FC $0001 $00A1 $5120 - Trigger

; --- BLOCKING WAIT 1 ---
.cmd21_wait_phase1:
        tst.b   COMM6                           ; $00E4F8: $4A39 $00A1 $512C - Check handshake
        bne.s   .cmd21_wait_phase1              ; $00E4FE: $66F8             - Loop until clear

; Phase 2: Send parameters D0 and D1
        move.w  d0,COMM4                        ; $00E500: $33C0 $00A1 $5128 - Write D0
        move.w  d1,COMM5                        ; $00E506: $33C1 $00A1 $512A - Write D1
        move.w  #HANDSHAKE_READY,COMM6          ; $00E50C: $33FC $0101 $00A1 $512C - Signal ready

; --- BLOCKING WAIT 2 ---
.cmd21_wait_phase2:
        tst.b   COMM6                           ; $00E514: $4A39 $00A1 $512C - Check handshake
        bne.s   .cmd21_wait_phase2              ; $00E51A: $66F8             - Loop until clear

; Phase 3: Send data pointer (no wait - SH2 processes async)
        move.l  a0,COMM4                        ; $00E51C: $23C8 $00A1 $5128 - Write A0
        move.w  #HANDSHAKE_READY,COMM6          ; $00E522: $33FC $0101 $00A1 $512C - Signal ready
        rts                                     ; $00E52A: $4E75             - Return

; ============================================================================
; Memory initialization ($00E52C-$00E5AA)
; ============================================================================
; Initializes three memory regions based on D0 parameter
; Parameters: D0 = selector (0, 1, or other)
; Uses: A0, A1, A2, A3, D1, D2
; ============================================================================
MemoryInit:
        lea     ($FFFF84A2).w,a0                ; $00E52C - Buffer A base
        lea     ($FFFF84C2).w,a1                ; $00E530 - Buffer B base
        lea     ($FFFF84E2).w,a2                ; $00E534 - Buffer C base

        clr.w   d2                              ; $00E538 - D2 = 0
        move.w  #$0007,d1                       ; $00E53A - D1 = 7 (loop counter)

.clear_loop:
        move.w  #$0000,(a0,d2.w)                ; $00E53E - Clear A[D2]
        move.w  #$0000,(a1,d2.w)                ; $00E544 - Clear B[D2]
        move.w  #$0000,(a2,d2.w)                ; $00E54A - Clear C[D2]
        addq.w  #2,d2                           ; $00E550 - D2 += 2
        dbra    d1,.clear_loop                  ; $00E552 - Loop 8 times

; Select address based on D0
        tst.w   d0                              ; $00E556 - Test D0
        bne.s   .check_one                      ; $00E558 - Branch if != 0
        lea     ($FFFF84A2).w,a0                ; $00E55A - Buffer A
        bra.w   .setup_table                    ; $00E55E

.check_one:
        cmpi.w  #$0001,d0                       ; $00E562 - Compare D0 with 1
        bne.w   .use_addr3                      ; $00E566
        lea     ($FFFF84C2).w,a0                ; $00E56A - Buffer B
        bra.w   .setup_table                    ; $00E56E

.use_addr3:
        lea     ($FFFF84E2).w,a0                ; $00E572 - Buffer C

.setup_table:
        lea     ($0088E5AC).l,a3                ; $00E576 - Load table address
        moveq   #0,d1                           ; $00E57C - D1 = 0

.copy_loop:
        move.w  ($FFFFA012).w,d1                ; $00E57E - Load table index
        add.w   d1,d1                           ; $00E582 - D1 *= 2 (word offset)
        adda.l  d1,a3                           ; $00E584 - A3 += D1
        clr.w   d2                              ; $00E586 - D2 = 0
        move.w  #$0007,d1                       ; $00E588 - D1 = 7 (loop counter)

.inner_loop:
        move.w  (a3)+,(a0,d2.w)                 ; $00E58C - Copy table entry to buffer[D2]
        addq.w  #2,d2                           ; $00E590 - D2 += 2
        dbra    d1,.inner_loop                  ; $00E592 - Loop 8 times
; ============================================================================
; VDP register manipulation ($00E596-$00E5AA)
; ============================================================================
; Reads VDP control register, shifts and validates value, then writes back
; Parameters: None
; Uses: D1, VDP control port ($A012)
; ============================================================================
VDPRegManipulate:
        move.w  ($FFFFA012).w,d1                ; $00E596 - Load current value
        addq.w  #1,d1                           ; $00E59A - Increment
        cmpi.w  #$0007,d1                       ; $00E59C - Compare with 7
        ble.w   .store_value                    ; $00E5A0 - Skip clear if <= 7
        clr.w   d1                              ; $00E5A4 - Wrap to 0
.store_value:
        move.w  d1,($FFFFA012).w                ; $00E5A6 - Store updated value
        rts                                     ; $00E5AA
        include "modules/68k/game/render/default_palette_color_data.asm"
        include "modules/68k/game/render/sh2_split_screen_display_init.asm"
        ROMDATA $00E88C,$00E90C

; ============================================================================
; Function: Jump Table Dispatcher ($00E90C-$00E926)
; ============================================================================
; Calls initialization function, loads an index from ($C87E), and dispatches
; to one of three handler functions via indexed jump table.
;
; Jump Table:
;   Index 0 ($00E91C): $0088E93A
;   Index 4 ($00E920): $0088EDDA
;   Index 8 ($00E924): $0088EEF2
;
; Uses: D0 (jump table index), A1 (target address)
; ============================================================================
        include "modules/68k/game/state/palette_scene_dispatch.asm"

; ============================================================================
; Function: Post-Dispatch Callback ($00E928-$00E938)
; ============================================================================
; Called after handler completion. Checks bit 6 of ($C80E); if clear,
; advances ($C87E) by 4 bytes.
;
; Uses: None (bit test and conditional increment only)
; ============================================================================
post_dispatch_callback:
        jsr     object_update(pc)               ; $00E928: $4EBA $CD5A (cross-section)
        btst    #6,($FFFFC80E).w                ; $00E92C - Test bit 6 of game state
        bne.s   .skip_advance                   ; $00E932 - Skip if set
        addq.w  #4,($FFFFC87E).w                ; $00E934 - Advance jump table index
.skip_advance:
        rts                                     ; $00E938
        include "modules/68k/game/render/sh2_geometry_transfer_and_palette_cycle_handler.asm"
        ROMDATA $00EAC2,$00EB76
; Padding: 94 bytes (47 words) of zeros from $EB76-$EBD2
        dcb.w   47, $0000
        ROMDATA $00EBD4,$00EC76
; Padding: 72 bytes (36 words) of zeros from $EC76-$ECBC
        dcb.w   36, $0000
        include "modules/68k/game/scene/sh2_scene_object_update_with_lookup_tables.asm"

; ============================================================================
; Function: SH2 Status Check and ROM Vector Setup ($00EEF2-$00EF30)
; ============================================================================
; Waits for SH2 Master CPU ready (COMM0 clear), clears COMM3, resets index
; at ($C87E), and writes ROM function pointers to ($FF0002) based on VINT
; enable flags.
;
; Memory writes:
;   ($C87E).W = $0000                    - Reset jump table index
;   ($FF0002).L = ROM function pointer   - Selected based on VINT flags
;
; BLOCKING: Polls COMM0 until clear (Master SH2 ready signal)
; Uses: A0 (scratch)
; ============================================================================
sh2_status_check_and_vector_setup:
.wait_master:
        tst.b   COMM0                           ; $00EEF2 - Test Master ready
        bne.s   .wait_master                    ; $00EEF8 - Loop until clear

        clr.b   COMM1_LO                        ; $00EEFA - Clear COMM1 low byte
        move.w  #$0000,($FFFFC87E).w           ; $00EF00 - Reset jump table index

        ; Write first ROM vector ($008926D2)
        move.l  #$008926D2,($00FF0002).l        ; $00EF06 - Default VINT handler

        ; Check VINT enable flags and conditionally write alternate vectors
        tst.b   ($FFFFA018).w                   ; $00EF10 - Test VINT enable flag 1
        bne.s   .done                           ; $00EF14 - Skip if set

        move.l  #$0088D4A4,($00FF0002).l        ; $00EF16 - Alternate vector 1

.check_second_flag:
        tst.b   ($FFFFA01F).w                   ; $00EF20 - Test VINT enable flag 2
        bne.s   .done                           ; $00EF24 - Skip if set

        move.l  #$0088D48A,($00FF0002).l        ; $00EF26 - Alternate vector 2

.done:
        rts                                     ; $00EF30

; ============================================================================
; Function: Table-Based Dual Dispatch with COMM Sync ($00EF32-$00EFA2)
; ============================================================================
; Selects data from two different tables based on flags, then dispatches to
; rendering functions. Each table entry contains a 4-byte address and a 2-byte
; parameter (6 bytes total). Index is computed as byte_value * 3 (for 6-byte
; entries accessed as longword + word).
;
; First dispatch:  Uses table at $0088EFA4, calls function at $00E9B4
; Second dispatch: Uses table at $0088EFB6, calls sh2_cmd_27 after COMM sync
;
; Parameters loaded from tables and passed to dispatch functions:
;   A0 = Longword from table[index*6]
;   D0 = Word from table[index*6 + 4]
;   D1 = Width parameter (#$0030 or #$0018)
;   D2 = Height parameter (#$0010)
;
; BLOCKING: Waits for COMM0 clear before second dispatch
; Uses: D0-D2, A0-A1
; ============================================================================
table_dual_dispatch:
        ; ---- First table dispatch ----
        moveq   #$00,d0                         ; $00EF32 - Clear D0
        tst.b   ($FFFFA01A).w                   ; $00EF34 - Test flag 1
        bne.s   .use_alt1_index                 ; $00EF38 - Branch if set
        move.b  ($FFFFA019).w,d0                ; $00EF3A - Load table index A
        bra.s   .dispatch1                      ; $00EF3E
.use_alt1_index:
        move.b  ($FFFFA01E).w,d0                ; $00EF40 - Load table index B

.dispatch1:
        lea     $0088EFA4.l,a1                  ; $00EF44 - Load table 1 base
        add.w   d0,d0                           ; $00EF4A - D0 *= 2
        move.w  d0,d1                           ; $00EF4C - D1 = D0
        add.w   d0,d0                           ; $00EF4E - D0 *= 2 (now *= 4)
        add.w   d1,d0                           ; $00EF50 - D0 = D0 + D1 (now *= 6)
        movea.l (a1,d0.w),a0                    ; $00EF52 - Load address from table
        move.w  ($04,a1,d0.w),d0                ; $00EF56 - Load word param
        move.w  #$0030,d1                       ; $00EF5A - Width = $30
        move.w  #$0010,d2                       ; $00EF5E - Height = $10
        jsr     sh2_cmd_27(pc)                  ; $00EF62: JSR (d16,PC) sh2_cmd_27

        ; ---- Second table dispatch ----
        moveq   #$00,d0                         ; $00EF66 - Clear D0
        tst.b   ($FFFFA01A).w                   ; $00EF68 - Test flag 1
        beq.s   .use_alt2_index                 ; $00EF6C - Branch if clear
        move.b  ($FFFFA019).w,d0                ; $00EF6E - Load table index A
        bra.s   .dispatch2                      ; $00EF72
.use_alt2_index:
        move.b  ($FFFFA01D).w,d0                ; $00EF74 - Load table index B

.dispatch2:
        lea     $0088EFB6.l,a1                  ; $00EF78 - Load table 2 base
        add.w   d0,d0                           ; $00EF7E - D0 *= 2
        move.w  d0,d1                           ; $00EF80 - D1 = D0
        add.w   d0,d0                           ; $00EF82 - D0 *= 4
        add.w   d1,d0                           ; $00EF84 - D0 *= 6
        movea.l (a1,d0.w),a0                    ; $00EF86 - Load address from table
        move.w  ($04,a1,d0.w),d0                ; $00EF8A - Load word param
        move.w  #$0018,d1                       ; $00EF8E - Width = $18
        move.w  #$0010,d2                       ; $00EF92 - Height = $10

.wait_comm_ready:
        tst.b   COMM0                           ; $00EF96 - Check COMM0 clear
        bne.s   .wait_comm_ready                ; $00EF9C - Wait until clear

        jsr     sh2_cmd_27(pc)                  ; $00EF9E: JSR (d16,PC) sh2_cmd_27
        rts                                     ; $00EFA2
        ROMDATA $00EFA4,$00EFC2
        include "modules/68k/sh2/comm_transfer_setup_a.asm"
        ROMDATA $00F034,$00F040
        include "modules/68k/sh2/comm_transfer_setup_b.asm"
        ROMDATA $00F0B2,$00F0BE
        include "modules/68k/sh2/comm_transfer_setup_c.asm"
        include "modules/68k/game/render/sh2_three_panel_display_init.asm"
        include "modules/68k/game/scene/scene_state_disp_with_color_tables.asm"
        include "modules/68k/game/render/multi_screen_palette_navigation_handler.asm"
        include "modules/68k/game/scene/sh2_multi_panel_object_update_orch.asm"
        ROMDATA $00F838,$00F85C
        include "modules/68k/sh2/sync_wait_reset.asm"
        include "modules/68k/display/palette_table_init.asm"
        include "modules/68k/game/render/sh2_multi_panel_tile_renderer.asm"
        ROMDATA $00FB24,$00FB36
        include "modules/68k/sh2/comm_transfer_block.asm"
        include "modules/68k/game/menu/time_trial_records_display_init.asm"
        include "modules/68k/game/menu/records_scene_state_disp.asm"
; ============================================================================
; Function: Name Entry Display Render Init ($01017A-$010201)
; ============================================================================
; Dispatched from records_scene_state_disp jump table (state 0).
; Initializes memory, updates objects, transfers character rendering data
; to SH2 framebuffer via sh2_send_cmd ($22). Two display modes selected
; by bit 1 of ($A014). Flows into name_entry_sh2_xfer_advance at $010200.
;
; Parameters: None (uses game state from Work RAM)
; Clobbers: D0, D1, A0, A1, A2 (plus callee clobbers)
; Calls: MemoryInit, object_update, name_entry_background_tile_transfer,
;        sh2_send_cmd, lap_time_digit_renderer_a
; ============================================================================
name_entry_display_render_init:
        clr.w   d0                              ; $01017A: D0 = 0 (select buffer A)
        bsr.w   MemoryInit                      ; $01017C: Initialize memory buffers
        jsr     object_update(pc)               ; $010180: $4EBA $B502 Update all objects
        bsr.w   name_entry_background_tile_transfer ; $010184: Transfer background tiles

; Send character region A to SH2 framebuffer
        movea.l #$0601AA00,a0                   ; $010188: SH2 framebuffer source
        movea.l #$2400C060,a1                   ; $01018E: SH2 SDRAM dest (cache-through)
        move.w  #$0038,d0                       ; $010194: Width = 56
        move.w  #$0010,d1                       ; $010198: Height = 16
        jsr     sh2_send_cmd(pc)                ; $01019C: $4EBA $E1BC Send command $22

; Render digit tiles (first set)
        lea     ($2402C0A0).l,a1                ; $0101A0: SH2 tile palette address
        lea     ($FFFFA032).w,a2                ; $0101A6: Work RAM source data
        bsr.w   lap_time_digit_renderer_a       ; $0101AA: Render character digits

; Select display mode based on game state flag
        btst    #1,($FFFFA014).w                ; $0101AE: Test display mode bit
        bne.s   .alt_display                    ; $0101B4: Branch if alternate mode

; Normal display mode: 72-pixel wide region
        movea.l #$0601AD80,a0                   ; $0101B6: SH2 framebuffer source B
        movea.l #$2400E050,a1                   ; $0101BC: SH2 SDRAM dest B
        move.w  #$0048,d0                       ; $0101C2: Width = 72
        move.w  #$0010,d1                       ; $0101C6: Height = 16
        jsr     sh2_send_cmd(pc)                ; $0101CA: $4EBA $E18E Send command $22
        bra.s   .continue                       ; $0101CE: Skip alternate path

; Alternate display mode: 104-pixel wide region
.alt_display:
        movea.l #$0601B200,a0                   ; $0101D0: SH2 framebuffer source C
        movea.l #$2400E038,a1                   ; $0101D6: SH2 SDRAM dest C
        move.w  #$0068,d0                       ; $0101DC: Width = 104
        move.w  #$0010,d1                       ; $0101E0: Height = 16
        jsr     sh2_send_cmd(pc)                ; $0101E4: $4EBA $E174 Send command $22

; Render digit tiles (second set)
.continue:
        lea     ($2402E0A0).l,a1                ; $0101E8: SH2 tile palette address B
        lea     ($FFFFC254).w,a2                ; $0101EE: Work RAM source data B
        bsr.w   lap_time_digit_renderer_a       ; $0101F2: Render character digits B

; Continue into name_entry_sh2_xfer_advance (spans section boundary)
        movea.l #$0601B880,a0                   ; $0101F6: SH2 framebuffer source D
        dc.w    $227C,$2401                     ; $0101FC: MOVEA.L #$24011050,A1 (3rd word $1050 at $010200 in next section)
