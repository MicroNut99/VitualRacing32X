; ============================================================================
; Sound Master Flag
; ROM Range: $031680-$031686 (8 bytes)
; ============================================================================
; Sets byte at A6+$38 to $80 (master sound flag).
;
; Entry: A6 = sound state pointer
; Uses: none
; Fields modified: A6+$38
; ============================================================================

sound_master_flag:
        move.b  #$80,$0038(a6)          ; Set master flag to $80
        rts
