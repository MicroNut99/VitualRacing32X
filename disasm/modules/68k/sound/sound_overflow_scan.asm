; ============================================================================
; Sound Overflow Scan
; ROM Range: $030AF8-$030B1A (36 bytes)
; ============================================================================
; Reads byte from A6+$02, adds to A6+$01. If carry (overflow),
; scans 10 entries at A6+$40 (spaced $30 bytes apart), incrementing
; $0E(A0) for each entry where byte at (A0) has bit 7 set.
;
; Entry: A6 = sound state pointer
; Uses: D0, D1, A0
; Fields accessed: A6+$01, A6+$02, A6+$40+n*$30
; ============================================================================

sound_overflow_scan:
        move.b  $0002(a6),d0            ; D0 = increment value
        beq.s   .return                 ; If zero, nothing to do
        add.b   d0,$0001(a6)            ; Add to accumulator
        bcc.s   .return                 ; If no carry, return
        lea     $0040(a6),a0            ; A0 = first channel entry
        moveq   #$30,d0                 ; D0 = entry stride (48 bytes)
        moveq   #9,d1                   ; D1 = loop counter (10 entries)
.loop:
        tst.b   (a0)                    ; Test channel status byte
        bpl.s   .skip                   ; If bit 7 clear, skip
        addq.b  #1,$000E(a0)            ; Increment overflow counter
.skip:
        adda.w  d0,a0                   ; Advance to next entry
        dbra    d1,.loop                ; Loop 10 times
.return:
        rts
