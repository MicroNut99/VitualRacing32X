; ============================================================================
; Sound Counter Check
; ROM Range: $030A72-$030A84 (20 bytes)
; ============================================================================
; Reads A6+$04 status byte. If zero, returns immediately.
; If non-zero, reads counter at A6+$06. If zero, branches to
; external handler. Otherwise decrements counter and returns.
;
; Entry: A6 = sound state pointer
; Uses: D0
; Fields accessed: A6+$04 (status), A6+$06 (counter)
; ============================================================================

sound_counter_check:
        moveq   #0,d0                   ; Clear D0
        move.b  $0004(a6),d0            ; D0 = status byte
        beq.s   .return                 ; If zero, return
        move.b  $0006(a6),d0            ; D0 = counter
        beq.s   fm_envelope_tick_update  ; $030A7E  beq.s → fm_envelope_tick_update
        subq.b  #1,$0006(a6)            ; Decrement counter
.return:
        rts
