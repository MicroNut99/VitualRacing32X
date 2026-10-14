; ============================================================================
; Arctangent Calculation (Segmented Table Lookup)
; ROM Range: $008FC8-$009040 (120 bytes)
; ============================================================================
; Segmented arctangent calculation using 3 ROM lookup tables.
; Input in D0 (signed), returns angle in D0.W.
;
; Entry: D0.L = input value (signed)
; Exit: D0.W = angle result
; Uses: D0, D1, D2, A1
; ============================================================================

atan2_calc:
        move.l  d0,d1                 ; Copy input
        bpl.s   .pos
        neg.l   d1                    ; |input|
.pos:
        cmpi.l  #$00000400,d1         ; Range 1 check
        bge.s   .range2
        andi.b  #$FC,d1               ; Mask low 2 bits
        asr.l   #1,d1                 ; Divide by 2
        lea     $00930202,a1          ; Table 1
        move.w  (a1,d1.l),d1          ; Lookup (D1.L index)
        ext.l   d1
        bra.s   .apply_sign
.range2:
        cmpi.l  #$00000D8F,d1         ; Range 2 check
        bge.s   .range3
        subi.l  #$00000400,d1
        andi.b  #$F0,d1               ; Mask low 4 bits
        asr.l   #3,d1                 ; Divide by 8
        lea     $00930402,a1          ; Table 2
        move.w  (a1,d1.l),d1          ; Lookup (D1.L index)
        ext.l   d1
        bra.s   .apply_sign
.range3:
        cmpi.l  #$0000517C,d1         ; Range 3 check
        bge.s   .large
        moveq   #$0B,d2               ; Shift count 11
        asr.l   d2,d1                 ; Divide by 2048
        addi.l  #$000000F4,d1         ; Offset into table 3
        bra.s   .apply_sign
.large:
        move.l  #$000000FE,d1         ; Default for very large
        cmpi.l  #$0000A2F8,d1         ; Extra large check
        blt.s   .apply_sign
        move.l  #$00000100,d1         ; Cap value
.apply_sign:
        tst.l   d0                    ; Check original sign
.check_sign:
        bpl.s   .no_negate
        neg.l   d1                    ; Negate result
.no_negate:
        asl.l   #6,d1                 ; Scale result
        move.w  d1,d0                 ; Result to D0
        rts
