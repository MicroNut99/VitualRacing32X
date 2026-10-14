; ============================================================================
; Sound Timer Decrement
; ROM Range: $030256-$03025C (8 bytes)
; ============================================================================
; Decrements counter at A5+$19. If result is zero, falls through
; to sound_state_reload. Otherwise returns.
;
; Entry: A5 = channel state pointer
; Uses: none
; Fields accessed: A5+$19 (counter)
; ============================================================================

sound_timer_dec:
        subq.b  #1,$0019(a5)            ; Decrement counter at $19
        beq.s   sound_state_reload      ; If zero, reload state
        rts
