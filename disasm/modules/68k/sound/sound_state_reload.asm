; ============================================================================
; Sound State Reload
; ROM Range: $03025E-$030278 (28 bytes)
; ============================================================================
; Reloads channel state from a pointer at A5+$14.
; Copies byte at (A0)+$01 to A5+$19. If A5+$1B is zero,
; also copies (A0)+$03 to A5+$1B and negates A5+$1A.
;
; Entry: A5 = channel state pointer
; Uses: A0
; Fields accessed: A5+$14 (pointer), A5+$19, A5+$1A, A5+$1B
; ============================================================================

sound_state_reload:
        movea.l $0014(a5),a0            ; A0 = saved data pointer
        move.b  $0001(a0),$0019(a5)     ; Copy byte at A0+1 to field $19
        tst.b   $001B(a5)               ; Test field $1B
        bne.s   sound_accumulate        ; If non-zero, skip to accumulate
        move.b  $0003(a0),$001B(a5)     ; Copy byte at A0+3 to field $1B
        neg.b   $001A(a5)               ; Negate field $1A
        rts
