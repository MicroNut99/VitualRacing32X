; ============================================================================
; Sound Subtract Field
; ROM Range: $0311A8-$0311B6 (16 bytes)
; ============================================================================
; Reads an indexed word from A6 structure, subtracts it from A5+$1E,
; then clears the indexed byte. D0.W contains the index (pre-doubled).
;
; Entry: D0 = index*2, A5 = channel state, A6 = sound state
; Uses: D1
; Fields accessed: A6+$12+D0.W (word), A5+$1E, A6+$10+D0.W (byte)
; ============================================================================

sound_subtract_field:
        move.w  $12(a6,d0.w),d1         ; D1 = indexed word value
        sub.w   d1,$001E(a5)            ; Subtract from position field
        moveq   #0,d1                   ; D1 = 0
        move.b  d1,$10(a6,d0.w)         ; Clear indexed status byte
        rts
