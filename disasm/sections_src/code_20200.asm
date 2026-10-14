; ============================================================================
; Code Section ($020200-$0221FF)
; Generated from ROM bytes - guaranteed accurate
; ============================================================================

        org     $020200

        ROMDATA $020200,$0203CC
; Original Slave idle loop (writes R0 to COMM6, loops forever)
; PATCH #1 REVERTED — all expansion ROM patches disabled for clean baseline.
; See: KNOWN_ISSUES.md § Slave SH2 Idle Loop at $0203CC
        dc.w    $D101        ; $0203CC - MOV.L @(4,PC),R1
        dc.w    $2102        ; $0203CE - MOV.L R0,@R1
        dc.w    $AFFE        ; $0203D0 - BRA $0203D0 (loop forever)
        dc.w    $0009        ; $0203D2 - NOP
        dc.w    $2000        ; $0203D4 - \ COMM6 address literal
        dc.w    $402C        ; $0203D6 - / (0x2000402C)
        ROMDATA $0203D8,$02046A
; Original Master dispatch (shift, table lookup, JSR to handler)
; PATCH #2 REVERTED — master_dispatch_hook caused COMM7 signal collision crash.
; See: KNOWN_ISSUES.md § COMM7 Signal Namespace Collision
; See: analysis/architecture/MASTER_SH2_DISPATCH_ANALYSIS.md
        dc.w    $4008        ; $02046A - SHLL2 R0 (cmd * 4 for table index)
        dc.w    $D107        ; $02046C - MOV.L @(28,PC),R1 → jump table at 0x06000780
        dc.w    $001E        ; $02046E - MOV.L @(R0,R1),R0 (load handler address)
        dc.w    $400B        ; $020470 - JSR @R0 (call handler, PR=$020474)
        dc.w    $0009        ; $020472 - NOP (delay slot)
        dc.w    $AFF4        ; $020474 - BRA $020460 (loop back to idle poll)
        dc.w    $0009        ; $020476 - NOP (delay slot)
        ROMDATA $020478,$02050C
; === VDP Wait Function (ORIGINAL - DO NOT MODIFY) ===
; This is called by Slave SH2 during rendering - critical for operation
vdp_wait_test:                   ; $02050C
        ROMDATA $02050C,$02051E
        dc.w    $0000        ; $02051E - next section starts here
        ROMDATA $020520,$020608
; --- Inline COMM7 check + cmd27 COMM-register processing (88 bytes + 40 NOP) ---
; Replaces original delay loop. Runs from SDRAM (no expansion ROM).
; Source: disasm/sh2/expansion/inline_slave_drain.asm
; Protocol: 68K writes params to COMM2-6 + doorbell COMM7=$0027.
;   Slave reads COMM2-6, clears COMM7, processes pixels, loops back.
; Uses ONLY COMM registers for parameter passing (documented shared memory).
        dc.w    $D812        ; $020608  MOV.L .comm7_addr,R8   (R8=&COMM7)
        dc.w    $6081        ; $02060A  MOV.W @R8,R0           ← check_comm7
        dc.w    $2008        ; $02060C  TST R0,R0
        dc.w    $891E        ; $02060E  BT .idle
        dc.w    $D111        ; $020610  MOV.L .comm_base,R1    (R1=$20004020)
        dc.w    $5312        ; $020612  MOV.L @(8,R1),R3       (data_ptr from COMM4+5)
        dc.w    $6213        ; $020614  MOV R1,R2
        dc.w    $7204        ; $020616  ADD #4,R2              (&COMM2)
        dc.w    $6421        ; $020618  MOV.W @R2,R4           (width)
        dc.w    $7202        ; $02061A  ADD #2,R2              (&COMM3)
        dc.w    $6521        ; $02061C  MOV.W @R2,R5           (height)
        dc.w    $6213        ; $02061E  MOV R1,R2
        dc.w    $720C        ; $020620  ADD #12,R2             (&COMM6)
        dc.w    $6621        ; $020622  MOV.W @R2,R6           (add_value)
        dc.w    $E000        ; $020624  MOV #0,R0
        dc.w    $2801        ; $020626  MOV.W R0,@R8           (clear COMM7)
        dc.w    $E020        ; $020628  MOV #$20,R0            ← cache-through
        dc.w    $4028        ; $02062A  SHLL16 R0              ($200000)
        dc.w    $4018        ; $02062C  SHLL8 R0               ($20000000)
        dc.w    $230B        ; $02062E  OR R0,R3               (ptr→$24xxxxxx)
        dc.w    $E702        ; $020630  MOV #2,R7
        dc.w    $4718        ; $020632  SHLL8 R7               (stride=$200)
        dc.w    $6933        ; $020634  MOV R3,R9              ← outer_loop
        dc.w    $6A43        ; $020636  MOV R4,R10
        dc.w    $6B90        ; $020638  MOV.B @R9,R11          ← inner_loop
        dc.w    $3B6C        ; $02063A  ADD R6,R11
        dc.w    $29B0        ; $02063C  MOV.B R11,@R9
        dc.w    $7901        ; $02063E  ADD #1,R9
        dc.w    $4A10        ; $020640  DT R10
        dc.w    $8BF9        ; $020642  BF .inner_loop
        dc.w    $337C        ; $020644  ADD R7,R3              ← next_row
        dc.w    $4510        ; $020646  DT R5
        dc.w    $8BF4        ; $020648  BF .outer_loop
        dc.w    $AFDE        ; $02064A  BRA .check_comm7       (check for more)
        dc.w    $0009        ; $02064C  NOP (delay slot)
        dc.w    $D303        ; $02064E  MOV.L .cmdloop,R3      ← idle
        dc.w    $432B        ; $020650  JMP @R3
        dc.w    $0009        ; $020652  NOP (delay slot)
        dc.w    $2000        ; $020654  literal: $2000402E (COMM7)
        dc.w    $402E        ; $020656
        dc.w    $2000        ; $020658  literal: $20004020 (COMM base)
        dc.w    $4020        ; $02065A
        dc.w    $0600        ; $02065C  literal: $06000592 (command_loop)
        dc.w    $0592        ; $02065E
; Remaining 40 bytes NOP padding to fill 128-byte slot
        dcb.w   20,$0009     ; $020660-$020687  NOP fill
        dc.w    $4F22        ; $020688
        dc.w    $E800        ; $02068A
        dc.w    $3AB7        ; $02068C
        dc.w    $8903        ; $02068E
        dc.w    $7A01        ; $020690
        dc.w    $7801        ; $020692
        dc.w    $AFFA        ; $020694
        dc.w    $0009        ; $020696
        dc.w    $4F26        ; $020698
        dc.w    $000B        ; $02069A
        ROMDATA $02069C,$02069E
        dc.w    $0009        ; $02069E
        dc.w    $2200        ; $0206A0
        dc.w    $0400        ; $0206A2
        dc.w    $5245        ; $0206A4
        dc.w    $4459        ; $0206A6
        dc.w    $574F        ; $0206A8
        dc.w    $524B        ; $0206AA
        dc.w    $444F        ; $0206AC
        dc.w    $4E45        ; $0206AE
        dc.w    $000B        ; $0206B0
        dc.w    $0009        ; $0206B2
        dc.w    $000B        ; $0206B4
        dc.w    $0009        ; $0206B6
        dc.w    $0009        ; $0206B8
        dc.w    $0009        ; $0206BA
        dc.w    $0009        ; $0206BC
        ROMDATA $0206BE,$020808
        dc.w    $0600        ; $020808  cmd $22 → $06005198, the original handler (VR32X V7)
        dc.w    $5198        ; $02080A
        ROMDATA $02080C,$020814
        dc.w    $0600        ; $020814  cmd $25 → $06005024, the original handler (VR32X V8)
        dc.w    $5024        ; $020816
        ROMDATA $020818,$022200
