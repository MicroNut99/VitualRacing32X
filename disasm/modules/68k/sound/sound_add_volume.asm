; ============================================================================
; Sound Add Volume
; ROM Range: $031554-$03155A (8 bytes)
; ============================================================================
; Reads a byte from stream (A4)+ and adds it to A5+$08 (volume).
;
; Entry: A4 = data stream, A5 = channel state
; Uses: D0
; Fields modified: A5+$08
; ============================================================================

sound_add_volume:
        move.b  (a4)+,d0                ; Read delta from stream
        add.b   d0,$0008(a5)            ; Add to volume field
        rts
