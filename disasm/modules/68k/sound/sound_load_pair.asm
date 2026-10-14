; ============================================================================
; Sound Load Pair
; ROM Range: $031240-$031248 (10 bytes)
; ============================================================================
; Reads one byte from (A4) without increment to A5+$12,
; then reads (A4)+ with increment to A5+$13.
; Both reads are from the same address (same byte value).
;
; Entry: A4 = data stream pointer, A5 = channel state
; Uses: none
; Fields written: A5+$12, A5+$13
; ============================================================================

sound_load_pair:
        move.b  (a4),$0012(a5)          ; Copy current stream byte to $12
        move.b  (a4)+,$0013(a5)         ; Copy same byte to $13, advance
        rts
