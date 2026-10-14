; ============================================================================
; Sound Set Position
; ROM Range: $0311D8-$0311E0 (10 bytes)
; ============================================================================
; Reads a byte from stream (A4)+, sign-extends to word,
; and stores to A5+$1E (position field).
;
; Entry: A4 = data stream pointer, A5 = channel state
; Uses: D0
; Fields written: A5+$1E
; ============================================================================

sound_set_position:
        move.b  (a4)+,d0                ; Read byte from stream
        ext.w   d0                      ; Sign extend to word
        move.w  d0,$001E(a5)            ; Store as position
        rts
