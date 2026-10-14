; ============================================================================
; Sound Timer Check
; ROM Range: $030242-$030254 (20 bytes)
; ============================================================================
; Tests bit 7 of A5+$0A. If clear, branches to RTS at $030290.
; If set, tests timer at A5+$18. If non-zero, decrements it and returns.
;
; Entry: A5 = channel state pointer
; Uses: none
; Fields accessed: A5+$0A (bit test), A5+$18 (timer)
; ============================================================================

sound_timer_check:
        btst    #7,$000A(a5)            ; Test bit 7 of flags
        dc.w    $6746                   ; BEQ.S $030290 (external RTS)
        tst.b   $0018(a5)               ; Test timer
        beq.s   sound_timer_dec         ; If zero, go to next handler
        subq.b  #1,$0018(a5)            ; Decrement timer
        rts
