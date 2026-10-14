; ============================================================================
; Sound Set All Channels
; ROM Range: $031650-$031664 (22 bytes)
; ============================================================================
; Reads a byte from stream (A4)+ and writes it to offset $02 of
; each of 10 channel entries (spaced $30 bytes apart) starting at A6+$40.
;
; Entry: A4 = data stream, A6 = sound state
; Uses: D0, D1, D2, A0
; Fields modified: A6+$40+n*$30+$02 for n=0..9
; ============================================================================

sound_set_all_channels:
        lea     $0040(a6),a0            ; A0 = first channel entry
        move.b  (a4)+,d0                ; D0 = value from stream
        moveq   #$30,d1                 ; D1 = stride (48 bytes)
        moveq   #9,d2                   ; D2 = counter (10 channels)
.loop:
        move.b  d0,$0002(a0)            ; Write to channel field $02
        adda.w  d1,a0                   ; Advance to next channel
        dbra    d2,.loop                ; Loop 10 times
        rts
