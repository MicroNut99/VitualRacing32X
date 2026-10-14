; ============================================================================
; sh2_object_and_sprite_update_orch — SH2 Object and Sprite Update Orchestrator
; ROM Range: $00DCD0-$00DE98 (456 bytes)
; Per-frame SH2 communication orchestrator. Sends DMA transfer, runs
; object_update + sprite_update, then transfers 3D geometry and sprite
; data via sh2_send_cmd. Computes text overlay addresses from palette
; index with bit-shift multiplication. Renders text overlays via
; text_render. Sends final sh2_cmd_27 for tile updates. Handles
; exit via button detection with fade-out transition ($A8 sound).
;
; Uses: D0, D1, D2, D3, D4, A0, A1, A2
; Calls: $00B684 (object_update), $00B6DA (sprite_update),
;        $00E35A (sh2_send_cmd), $00E3B4 (sh2_cmd_27),
;        $00E466 (text_render), $00E52C (dma_transfer)
; Confidence: high
; ============================================================================

; --- Per-frame init: memory, objects, sprites ---
sh2_object_and_sprite_update_orch:
        CLR.W  D0                               ; $00DCD0
        jsr     MemoryInit(pc)          ; $4EBA $0858
        jsr     object_update(pc)       ; $4EBA $D9AC
        jsr     animated_seq_player+10(pc); $4EBA $D9FE
; --- Send 3D geometry to SH2 ---
.wait_comm_ready:
        TST.B  COMM0_HI                        ; $00DCDE ; SH2 busy?
        BNE.S  .wait_comm_ready                 ; $00DCE4
        MOVEA.L #$06037000,A0                   ; $00DCE6 ; 3D geo src (SDRAM)
        MOVEA.L #$24018010,A1                   ; $00DCEC ; frame buf dst
        MOVE.W  #$0120,D0                       ; $00DCF2 ; width = 288
        MOVE.W  #$0030,D1                       ; $00DCF6 ; height = 48
        DC.W    $6100,$065E         ; BSR.W  $00E35A; $00DCFA ; sh2_send_cmd
; --- Send overlay tiles (5 panels, bit-masked) ---
        BTST    #7,(-600).W                     ; $00DCFE ; overlays disabled?
        BNE.W  .send_sprite_data                ; $00DD04 ; skip overlays
        MOVEA.L #$0603A600,A0                   ; $00DD08 ; overlay base addr
        MOVEQ   #$00,D3                         ; $00DD0E ; panel index
        MOVE.W  #$0004,D4                       ; $00DD10 ; 5 panels (0-4)
.overlay_loop:
        BTST    D3,(-4345).W                    ; $00DD14 ; panel enabled?
        BEQ.S  .next_overlay                    ; $00DD18 ; skip disabled
        LEA     $0088DEB6,A1                    ; $00DD1A ; overlay addr table
        MOVE.W  D3,D0                           ; $00DD20 ; index
        ADD.W   D0,D0                           ; $00DD22 ; *4 (longword)
        ADD.W   D0,D0                           ; $00DD24
        MOVEA.L $00(A1,D0.W),A1                 ; $00DD26 ; dest address
        MOVE.W  #$0010,D0                       ; $00DD2A ; width = 16
        MOVE.W  #$0010,D1                       ; $00DD2E ; height = 16
        DC.W    $6100,$0626         ; BSR.W  $00E35A; $00DD32 ; sh2_send_cmd
.next_overlay:
        ADDQ.W  #1,D3                           ; $00DD36 ; next panel
        DBRA    D4,.overlay_loop                ; $00DD38
; --- Send sprite data block ---
.send_sprite_data:
        MOVEA.L #$0603B600,A0                   ; $00DD3C ; sprite src (SDRAM)
        MOVEA.L #$24014010,A1                   ; $00DD42 ; sprite dst
        MOVE.W  #$0120,D0                       ; $00DD48 ; width = 288
        MOVE.W  #$0018,D1                       ; $00DD4C ; height = 24
        DC.W    $6100,$0608         ; BSR.W  $00E35A; $00DD50 ; sh2_send_cmd
; --- Text overlay 1: compute address from palette index ---
; Address = base + (cam_idx * 16 * 4 + cam_idx * 16) * 2
; This is cam_idx * 80 (multiply via shifts+adds)
        LEA     $24034850,A1                    ; $00DD54 ; SH2 text dest
        LEA     (-4344).W,A2                    ; $00DD5A ; text data base
        ADDA.L  (-24536).W,A2                   ; $00DD5E ; + scroll offset
        MOVEQ   #$00,D0                         ; $00DD62
        MOVE.B  (-24551).W,D0                   ; $00DD64 ; cam/palette index
        ADD.W   D0,D0                           ; $00DD68 ; *2
        ADD.W   D0,D0                           ; $00DD6A ; *4
        ADD.W   D0,D0                           ; $00DD6C ; *8
        ADD.W   D0,D0                           ; $00DD6E ; *16
        MOVE.W  D0,D1                           ; $00DD70 ; save *16
        ADD.W   D0,D0                           ; $00DD72 ; *32
        ADD.W   D0,D0                           ; $00DD74 ; *64
        ADD.W   D1,D0                           ; $00DD76 ; *80 total
        ADD.W   D0,D0                           ; $00DD78 ; *160 (bytes)
        ADDA.L  D0,A2                           ; $00DD7A ; offset into table
        BTST    #7,(-600).W                     ; $00DD7C ; override mode?
        BEQ.W  .use_text_addr                   ; $00DD82
        LEA     $0088DECA,A2                    ; $00DD86 ; use fixed addr
.use_text_addr:
        jsr     ByteProcessLoop(pc)     ; $4EBA $06D8 ; render text 1
; --- Text overlay 2: second text block with different base ---
        LEA     $240348E8,A1                    ; $00DD90 ; SH2 text dest 2
        LEA     (-1464).W,A2                    ; $00DD96 ; text data base 2
        MOVEQ   #$00,D0                         ; $00DD9A
        MOVE.B  (-335).W,D0                     ; $00DD9C ; palette slot A
; multiply by 24: idx*8 + idx*16 = idx*24
        ADD.W   D0,D0                           ; $00DDA0 ; *2
        ADD.W   D0,D0                           ; $00DDA2 ; *4
        ADD.W   D0,D0                           ; $00DDA4 ; *8
        MOVE.W  D0,D1                           ; $00DDA6 ; save *8
        ADD.W   D0,D0                           ; $00DDA8 ; *16
        ADD.W   D1,D0                           ; $00DDAA ; *24 total
        ADD.W   D0,D0                           ; $00DDAC ; *48 (bytes)
        ADDA.L  D0,A2                           ; $00DDAE ; offset into table
; add cam_idx sub-offset (*8 + 4)
        MOVEQ   #$00,D0                         ; $00DDB0
        MOVE.B  (-24551).W,D0                   ; $00DDB2 ; cam/palette index
        ADD.W   D0,D0                           ; $00DDB6 ; *2
        ADD.W   D0,D0                           ; $00DDB8 ; *4
        ADD.W   D0,D0                           ; $00DDBA ; *8
        ADDQ.W  #4,D0                           ; $00DDBC ; +4 header offset
        ADDA.L  D0,A2                           ; $00DDBE ; final addr
        BTST    #7,(-600).W                     ; $00DDC0 ; override mode?
        BEQ.W  .use_text_addr_2                 ; $00DDC6
        LEA     $0088DECA,A2                    ; $00DDCA ; use fixed addr
.use_text_addr_2:
        jsr     ByteProcessLoop(pc)     ; $4EBA $0694 ; render text 2
; --- Send tile update via SH2 cmd 27 ---
        MOVEQ   #$00,D0                         ; $00DDD4
        MOVE.B  (-24551).W,D0                   ; $00DDD6 ; cam index
; lookup from 6-byte entry table (ptr:4 + param:2)
        LEA     $0088DE98,A1                    ; $00DDDA ; tile cmd table
        ADD.W   D0,D0                           ; $00DDE0 ; *2
        MOVE.W  D0,D1                           ; $00DDE2 ; save *2
        ADD.W   D0,D0                           ; $00DDE4 ; *4
        ADD.W   D1,D0                           ; $00DDE6 ; *6 total
        MOVEA.L $00(A1,D0.W),A0                 ; $00DDE8 ; tile src addr
        MOVE.W  $04(A1,D0.W),D0                 ; $00DDEC ; tile param
        MOVE.W  #$0030,D1                       ; $00DDF0 ; width = 48
        MOVE.W  #$0010,D2                       ; $00DDF4 ; height = 16
.wait_comm_ready_2:
        TST.B  COMM0_HI                        ; $00DDF8 ; SH2 busy?
        BNE.S  .wait_comm_ready_2               ; $00DDFE
        bsr.w   sh2_cmd_27              ; $6100 $05B2 ; send tile cmd
; --- Frame timing + exit state machine ---
        MOVE.W  #$0018,$00FF0008                ; $00DE04 ; V-INT period = 24
        CMPI.W  #$0001,(-24532).W               ; $00DE0C ; fade state 1?
        BEQ.W  .check_fade_done                 ; $00DE12
        CMPI.W  #$0002,(-24532).W               ; $00DE16 ; fade state 2?
        BEQ.W  .check_fade_complete             ; $00DE1C
; --- Button input ---
        MOVE.W  (-14228).W,D1                   ; $00DE20 ; P1 buttons
        ANDI.B  #$E0,D1                         ; $00DE24 ; A/B/C mask
        BNE.S  .begin_fadeout                    ; $00DE28 ; action → exit
        MOVE.W  (-14228).W,D1                   ; $00DE2A ; re-read buttons
        ANDI.B  #$10,D1                         ; $00DE2E ; Start mask
        BNE.S  .set_exit_flag                   ; $00DE32 ; Start → exit
        SUBQ.W  #8,(-14210).W                   ; $00DE34 ; tick timer
        BRA.W  .finish                          ; $00DE38
.set_exit_flag:
        ST      (-24552).W                      ; $00DE3C ; set exit flag
; --- Begin exit transition ---
.begin_fadeout:
        MOVE.B  #$A8,(-14172).W                 ; $00DE40 ; SFX: confirm
        MOVE.B  #$01,(-14327).W                 ; $00DE46 ; fade flag 1
        MOVE.B  #$01,(-14326).W                 ; $00DE4C ; fade flag 2
        BSET    #7,(-14322).W                   ; $00DE52 ; trigger fade-out
        MOVE.B  #$01,(-14334).W                 ; $00DE58 ; transition active
        MOVE.W  #$0002,(-24532).W               ; $00DE5E ; state → phase 2
        BRA.W  .dec_timer                       ; $00DE64
; --- Fade state handlers ---
.check_fade_done:
        BTST    #6,(-14322).W                   ; $00DE68 ; phase 1 done?
        BNE.S  .dec_timer                       ; $00DE6E ; still fading
        CLR.W  (-24532).W                       ; $00DE70 ; reset state
        BRA.W  .dec_timer                       ; $00DE74
.check_fade_complete:
        BTST    #7,(-14322).W                   ; $00DE78 ; phase 2 done?
        BNE.S  .dec_timer                       ; $00DE7E ; still fading
        CLR.W  (-24532).W                       ; $00DE80 ; reset state
        ADDQ.W  #4,(-14210).W                   ; $00DE84 ; advance scene
        BRA.W  .finish                          ; $00DE88
.dec_timer:
        SUBQ.W  #8,(-14210).W                   ; $00DE8C ; tick timer
.finish:
        MOVE.B  #$01,(-14303).W                 ; $00DE90 ; frame ready flag
        RTS                                     ; $00DE96
