; ============================================================================
; conditional_update_check ($006D00-$006D2E) — Conditional Update Check
; ============================================================================
; CODE: 48 bytes — BSR target called by conditional_pos_add,
; conditional_speed_add, conditional_pos_subtract, conditional_speed_subtract.
; Tests bit 2 of $C313, selects offset, adds from $C8A0 twice, builds
; address into $FF301A, and loops comparing entries.
; Falls through to return_zero_d1 ($006D30) on no match.
; BEQ.S to return_one_d1 ($006D34) on match.
; ============================================================================
conditional_update_check:
        moveq   #0,D7                           ; $006D00  default offset = 0
        btst    #2,($FFFFC313).w                ; $006D02  bit 2 set?
        beq.s   .add_offset                     ; $006D08  no → keep D7=0
        moveq   #4,D7                           ; $006D0A  yes → D7=4
.add_offset:
        add.w   ($FFFFC8A0).w,D7                ; $006D0C  D7 += frame counter
        add.w   ($FFFFC8A0).w,D7                ; $006D10  D7 += frame counter (x2)
        lea     $00FF301A,A2                    ; $006D14  A2 → entity table base
        movea.l (A2,D7.W),A1                    ; $006D1A  A1 → table entry
        move.w  ($FFFFC0BA).w,D1                ; $006D1E  D1 = comparison value
        move.w  (A1)+,D7                        ; $006D22  D7 = entry count, A1 past count
.loop:
        cmp.w   (A1),D1                         ; $006D24  compare entry vs D1
        beq.s   return_one_d1                   ; $006D26  match → return 1
        lea     $0010(A1),A1                    ; $006D28  advance to next entry
        dbf     D7,.loop                        ; $006D2C  loop D7+1 times
