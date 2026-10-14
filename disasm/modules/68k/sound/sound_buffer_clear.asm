; ============================================================================
; Sound Buffer Clear
; ROM Range: $030BE0-$030BF4 (22 bytes)
; ============================================================================
; Clears 120 longwords ($1E0 bytes) starting at A6+$40,
; then sets byte at A6+$09 to $80.
;
; Entry: A6 = sound state pointer
; Uses: D0, A0
; Fields written: A6+$40 through A6+$21F, A6+$09
; ============================================================================

sound_buffer_clear:
        lea     $0040(a6),a0            ; A0 = buffer start
        move.w  #$0077,d0               ; D0 = 119 (clear 120 longs)
.loop:
        clr.l   (a0)+                   ; Clear 4 bytes
        dbra    d0,.loop                ; Loop 120 times
        move.b  #$80,$0009(a6)          ; Set master flag byte
        rts
