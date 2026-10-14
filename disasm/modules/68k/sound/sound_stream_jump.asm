; ============================================================================
; Sound Stream Jump
; ROM Range: $031502-$03150C (12 bytes)
; ============================================================================
; Reads a big-endian 16-bit word from the data stream (A4),
; adds it as a signed displacement to A4, then adjusts by -1.
; Effectively a relative jump within the sound data stream.
;
; Entry: A4 = data stream pointer
; Uses: D0
; Modifies: A4 (repositioned)
; ============================================================================

sound_stream_jump:
        move.b  (a4)+,d0                ; Read high byte
        lsl.w   #8,d0                   ; Shift to high byte position
        move.b  (a4)+,d0                ; Read low byte (merge)
        adda.w  d0,a4                   ; Add 16-bit displacement to A4
        subq.w  #1,a4                   ; Adjust by -1
        rts
