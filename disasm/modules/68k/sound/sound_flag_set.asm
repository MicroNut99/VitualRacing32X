; ============================================================================
; Sound Flag Set
; ROM Range: $03155C-$031562 (8 bytes)
; ============================================================================
; Sets bit 7 of field $0A at A5 (enables channel processing).
;
; Entry: A5 = channel state pointer
; Uses: none
; Fields modified: A5+$0A (bit 7 set)
; ============================================================================

sound_flag_set:
        bset    #7,$000A(a5)            ; Set bit 7 of flags
        rts
