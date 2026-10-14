; ============================================================================
; Button Bit Dispatcher (7 Bit Tests)
; ROM Range: $006C88-$006CDC (84 bytes)
; ============================================================================
; Category: game
; Purpose: If SH2 buffer ($FF3000) == 0: calls sprite_table_init.
;   Reads $C86E (P2 controller byte A) into D1, sets D0 = $30
;   (or $08 if bit 6 clear). Tests bits 2,3,1,0,4,5,7 of D1 and
;   branches to individual handlers past this function for each set bit.
;   Falls through to RTS if no bits set.
;
; Uses: D0, D1
; RAM:
;   $C86E: P2 controller byte A (byte, tested bit-by-bit)
; Calls:
;   $006C46: sprite_table_init
; Branch targets (all past fn):
;   $006D38: bit 2 handler
;   $006D3E: bit 3 handler
;   $006D44: bit 1 handler
;   $006D4A: bit 0 handler
;   $006D50: bit 4 handler
;   $006D6E: bit 5 handler
;   $006D8C: bit 7 handler
; ============================================================================

button_bit_disp:
        tst.w   $00FF3000                      ; $006C88  SH2 buffer active?
        bne.s   .skip_init                      ; $006C8E  yes → skip
        jsr     tile_block_dma_setup(pc); $4EBA $FFB4
.skip_init:
        move.b  ($FFFFC86E).w,D1               ; $006C94  D1 = P2 controller byte A
        moveq   #$30,D0                         ; $006C98  D0 = $30 (default)
        btst    #6,D1                           ; $006C9A  bit 6 set?
        bne.s   .test_bits                      ; $006C9E  yes → keep $30
        moveq   #$08,D0                         ; $006CA0  D0 = $08 (alt value)
.test_bits:
        btst    #2,D1                           ; $006CA2  bit 2?
        bne.w   sub_x_position                  ; $006CA6  bit 2 handler
        btst    #3,D1                           ; $006CAA  bit 3?
        bne.w   add_x_position                  ; $006CAE  bit 3 handler
        btst    #1,D1                           ; $006CB2  bit 1?
        bne.w   sub_y_position                  ; $006CB6  bit 1 handler
        btst    #0,D1                           ; $006CBA  bit 0?
        bne.w   add_y_position                  ; $006CBE  bit 0 handler
        btst    #4,D1                           ; $006CC2  bit 4?
        bne.w   object_pos_table_lookup         ; $006CC6  bit 4 handler
        btst    #5,D1                           ; $006CCA  bit 5?
        bne.w   position_table_lookup           ; $006CCE  bit 5 handler
        btst    #7,D1                           ; $006CD2  bit 7?
        bne.w   steering_calc_reg_safe_wrapper  ; $006CD6  bit 7 handler
        rts                                     ; $006CDA
