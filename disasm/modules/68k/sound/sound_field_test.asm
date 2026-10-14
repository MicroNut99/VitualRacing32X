; ============================================================================
; Sound Field Test
; ROM Range: $030292-$03029C (12 bytes)
; ============================================================================
; Tests word at A5+$10. If zero, sets bit 1 of (A5) and returns.
; If non-zero, branches to external handler at $0302A6.
;
; Entry: A5 = channel state pointer
; Uses: D6
; Fields accessed: A5+$10, (A5) bit 1
; ============================================================================

sound_field_test:
        move.w  $0010(a5),d6            ; D6 = field $10
        dc.w    $660E                   ; BNE.S $0302A6 (external handler)
        bset    #1,(a5)                 ; Set bit 1 of status byte
        rts
