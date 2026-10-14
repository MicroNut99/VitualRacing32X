; ============================================================================
; Sound Add Transpose
; ROM Range: $0312AC-$0312B2 (8 bytes)
; ============================================================================
; Reads a byte from stream (A4)+ and adds it to A5+$09 (transpose).
;
; Entry: A4 = data stream, A5 = channel state
; Uses: D0
; Fields modified: A5+$09
; ============================================================================

sound_add_transpose:
        move.b  (a4)+,d0                ; Read transpose delta from stream
        add.b   d0,$0009(a5)            ; Add to transpose field
        rts
