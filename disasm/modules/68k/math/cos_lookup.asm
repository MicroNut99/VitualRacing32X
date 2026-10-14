; ============================================================================
; Cosine Table Lookup
; ROM Range: $008F9C-$008FB0 (20 bytes)
; ============================================================================
; Looks up cosine value from ROM table at $930000.
;
; Entry: D0.W = angle
; Exit: D0.W = cosine value
; Uses: D0, A1
; ============================================================================

cos_lookup:
        lea     $00930000,a1          ; Trig table
        subi.w  #$0200,d0             ; Offset angle
        add.w   d0,d0                 ; Word index
        move.w  (a1,d0.w),d0          ; Table lookup
        neg.w   d0                    ; Negate for cosine
        rts
