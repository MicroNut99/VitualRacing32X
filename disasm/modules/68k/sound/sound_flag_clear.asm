; ============================================================================
; Sound Flag Clear
; ROM Range: $031564-$03156A (8 bytes)
; ============================================================================
; Clears bit 7 of field $0A at A5 (disables channel processing).
;
; Entry: A5 = channel state pointer
; Uses: none
; Fields modified: A5+$0A (bit 7 cleared)
; ============================================================================

sound_flag_clear:
        bclr    #7,$000A(a5)            ; Clear bit 7 of flags
        rts
