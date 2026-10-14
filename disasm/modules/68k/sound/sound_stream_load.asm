; ============================================================================
; Sound Stream Load
; ROM Range: $030200-$030218 (26 bytes)
; ============================================================================
; Reads sequential bytes from a data stream (A0)+ into channel state fields
; at A5+$18/$19/$1A/$1B, with the last byte right-shifted by 1.
; Clears word at A5+$1C.
;
; Entry: A0 = data stream pointer, A5 = channel state pointer
; Uses: D0
; Fields written: A5+$18, A5+$19, A5+$1A, A5+$1B, A5+$1C
; ============================================================================

sound_stream_load:
        move.b  (a0)+,$0018(a5)         ; Read stream byte to field $18
        move.b  (a0)+,$0019(a5)         ; Read stream byte to field $19
        move.b  (a0)+,$001A(a5)         ; Read stream byte to field $1A
        move.b  (a0)+,d0                ; Read stream byte
        lsr.b   #1,d0                   ; Shift right by 1
        move.b  d0,$001B(a5)            ; Store to field $1B
        clr.w   $001C(a5)               ; Clear word at field $1C
        rts
