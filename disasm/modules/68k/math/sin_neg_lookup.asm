; ============================================================================
; Sine Negated Lookup (3rd Quadrant)
; ROM Range: $008FB0-$008FC6 (22 bytes)
; ============================================================================
; Looks up negated sine value (offset by -$400).
;
; Entry: D0.W = angle
; Exit: D0.W = -sin(angle - $400)
; Uses: D0, A1
; ============================================================================

sin_neg_lookup:
        lea     $00930000,a1          ; Trig table
        subi.w  #$0400,d0             ; Offset by quadrant
        neg.w   d0
        add.w   d0,d0                 ; Word index
        move.w  (a1,d0.w),d0          ; Table lookup
        neg.w   d0                    ; Negate result
        rts
