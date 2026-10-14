; ============================================================================
; Wait For V-Blank
; ROM Range: $004998-$0049AA (18 bytes)
; ============================================================================
; Waits for V-blank by setting VINT_STATE and halting the 68K with STOP.
; V-INT (level 6) will wake the CPU since STOP sets SR to level 3.
; The V-INT handler clears VINT_STATE before returning via RTE.
;
; Entry: none
; Uses: SR (set to $2300 by STOP, then restored by V-INT's RTE)
; ============================================================================

wait_for_vblank:
        move.w  #$0004,VINT_STATE.w             ; $004998: $31FC $0004 $C87A - request V-INT state 1
        stop    #$2300                          ; $00499E: $4E72 $2300 - halt until interrupt
        tst.w   VINT_STATE.w                    ; $0049A2: V-INT cleared $C87A? (H-INT filter)
        bne.s   wait_for_vblank+6               ; $0049A6: no → back to STOP (spurious wake)
        rts                                     ; $0049A8: $4E75
