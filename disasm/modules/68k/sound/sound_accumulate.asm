; ============================================================================
; Sound Accumulate
; ROM Range: $03027A-$030290 (24 bytes)
; ============================================================================
; Decrements field $1B, then accumulates a signed byte from field $1A
; into the word at field $1C, and adds field $10 to the result in D6.
;
; Entry: A5 = channel state pointer
; Exit: D6 = accumulated value + field $10
; Uses: D6
; Fields accessed: A5+$1A, A5+$1B, A5+$1C, A5+$10
; ============================================================================

sound_accumulate:
        subq.b  #1,$001B(a5)            ; Decrement counter at $1B
        move.b  $001A(a5),d6            ; D6 = signed delta from $1A
        ext.w   d6                      ; Sign extend to word
        add.w   $001C(a5),d6            ; D6 += accumulator at $1C
        move.w  d6,$001C(a5)            ; Store back to accumulator
        add.w   $0010(a5),d6            ; D6 += base value from $10
        rts
