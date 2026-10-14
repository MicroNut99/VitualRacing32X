; ============================================================================
; Sound Channel Mute
; ROM Range: $03156C-$031572 (8 bytes)
; ============================================================================
; Clears byte at A6+$00 (mutes channel by zeroing status).
;
; Entry: A6 = sound state pointer
; Uses: D0
; Fields modified: A6+$00
; ============================================================================

sound_channel_mute:
        moveq   #0,d0                   ; D0 = 0
        move.b  d0,$0000(a6)            ; Clear channel status
        rts
