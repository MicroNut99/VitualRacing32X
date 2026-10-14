; ============================================================================
; Sine Table Lookup
; ROM Range: $008F88-$008F9C (20 bytes)
; ============================================================================
; Looks up sine value from ROM table at $930000.
; Input angle offset by -$200 and negated.
;
; Entry: D0.W = angle
; Exit: D0.W = sine value
; Uses: D0, A1
; ============================================================================

sin_lookup:
        lea     $00930000,a1          ; Trig table
        subi.w  #$0200,d0             ; Offset angle
        neg.w   d0
        add.w   d0,d0                 ; Word index
        move.w  (a1,d0.w),d0          ; Table lookup
        rts
