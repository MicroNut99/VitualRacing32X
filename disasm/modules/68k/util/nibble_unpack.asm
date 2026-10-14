; ============================================================================
; Nibble Unpack (4 bytes to 7 nibbles)
; ROM Range: $00839A-$0083BC (34 bytes)
; ============================================================================
; Unpacks 4 bytes from (A4) into 7 nibble-separated bytes at (A1)+.
; Bytes 0,1,3 split into high/low nibbles; byte 2 stored as-is.
;
; Entry: A4 = source (4 bytes), A1 = destination (7 bytes)
; Uses: D1, D2, A1 (advances)
; ============================================================================

nibble_unpack:
        move.b  (a4),d1               ; Read byte 0
        bsr.s   .split_nibble
        move.b  $0001(a4),d1          ; Read byte 1
        bsr.s   .split_nibble
        move.b  $0002(a4),d1          ; Read byte 2
        move.b  d1,(a1)+              ; Store as-is
        move.b  $0003(a4),d1          ; Read byte 3 (falls through)
.split_nibble:
        move.b  d1,d2
        lsr.b   #4,d2                 ; High nibble
        move.b  d2,(a1)+
        andi.b  #$0F,d1              ; Low nibble
        move.b  d1,(a1)+
        rts
