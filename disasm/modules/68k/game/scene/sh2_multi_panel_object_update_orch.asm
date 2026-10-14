; ============================================================================
; sh2_multi_panel_object_update_orch — SH2 Multi-Panel Object Update Orchestrator
; ROM Range: $00F682-$00F838 (438 bytes)
; Data prefix (~96 bytes: SH2 command tables for single/dual-screen
; tile transfer configurations). Per-frame update: sends SH2 commands
; from table, calls internal renderer at $00F916, sends additional
; tile blocks, performs palette switch via $00F88C. Calls object/
; sprite update. Handles dual-player exit with palette save per-panel
; and fade-out transition. Calls $00FB36 during fade states.
;
; Uses: D0, D1, D2, D3, D6, A0, A1, A2
; Calls: $00B684 (object_update), $00B6DA (sprite_update),
;        $00E35A (sh2_send_cmd), $00F88C (palette_switch)
; Confidence: high
; ============================================================================

; --- DATA: SH2 tile transfer command tables ---
; Single-screen config (4 entries: src.L, dst.L, width.W, height.W)
sh2_multi_panel_object_update_orch:
        DC.W    $0603                           ; $00F682 ; (data: SH2 addrs)
        CMP.B  D0,D3                            ; $00F684
        DC.W    $0401                           ; $00F686
        MOVE.L  -(A4),D0                        ; $00F688
        ORI.W  #$0010,-(A0)                     ; $00F68A
        DC.W    $0603                           ; $00F68E
        CMP.B  D0,D6                            ; $00F690
        DC.W    $0401                           ; $00F692
        NEGX.B (A4)                             ; $00F694
        ORI.L  #$00100603,D0                    ; $00F696
        and.b   d0,d2                   ; $C400
        DC.W    $0401                           ; $00F69E
        MOVEQ   #$30,D0                         ; $00F6A0
        DC.W    $0048                           ; $00F6A2
        DC.W    $0010                           ; $00F6A4
; Dual-screen config (4 entries)
        DC.W    $0603                           ; $00F6A6
        and.l   d0,d4                   ; $C880
        DC.W    $0401                           ; $00F6AA
        SUB.B  (A0)+,D0                         ; $00F6AC
        ORI.W  #$0020,($0603).W                 ; $00F6AE
        CMP.B  D0,D3                            ; $00F6B4
        DC.W    $0401                           ; $00F6B6
        MOVE.L  #$00600010,(A0)                 ; $00F6B8
        DC.W    $0603                           ; $00F6BE
        CMP.B  D0,D6                            ; $00F6C0
        DC.W    $0401                           ; $00F6C2
        NEGX.L $0080(A4)                        ; $00F6C4
        DC.W    $0010                           ; $00F6C8
        DC.W    $0603                           ; $00F6CA
        and.b   d0,d2                   ; $C400
        DC.W    $0401                           ; $00F6CE
        MOVEQ   #-$38,D0                        ; $00F6D0
        DC.W    $0048                           ; $00F6D2
        DC.W    $0010                           ; $00F6D4
        DC.W    $0603                           ; $00F6D6
        and.l   d0,d4                   ; $C880
        DC.W    $0401                           ; $00F6DA
        SUB.L  $78(A0,D0.W),D0                  ; $00F6DC
        DC.W    $0020                           ; $00F6E0
; --- CODE: wait for SH2, render tiles, send cmd table ---
.wait_comm_ready:
        TST.B  COMM0_HI                        ; $00F6E2 ; SH2 busy?
        BNE.S  .wait_comm_ready                 ; $00F6E8
        bsr.w   sh2_multi_panel_tile_renderer+32; $6100 $022A ; render tiles
; send 3 SH2 commands from table (12 bytes each)
        LEA     $0088F838,A2                    ; $00F6EE ; cmd table ptr
        MOVE.W  #$0002,D2                       ; $00F6F4 ; 3 commands (0-2)
.send_cmd_loop:
        MOVEA.L (A2)+,A0                        ; $00F6F8 ; src addr
        MOVEA.L (A2)+,A1                        ; $00F6FA ; dst addr
        MOVE.W  (A2)+,D0                        ; $00F6FC ; width
        MOVE.W  (A2)+,D1                        ; $00F6FE ; height
        DC.W    $4EBA,$EC58         ; JSR     $00E35A(PC); $00F700 ; sh2_send_cmd
        DBRA    D2,.send_cmd_loop                ; $00F704
; --- Per-frame object/palette update ---
        CLR.W  D0                               ; $00F708
        MOVE.B  (-24549).W,D0                   ; $00F70A ; panel config index
        bsr.w   palette_table_init      ; $6100 $017C ; init palette
        jsr     object_update(pc)       ; $4EBA $BF70
        jsr     animated_seq_player+10(pc); $4EBA $BFC2
; --- State machine: browsing / fade transitions ---
        CMPI.W  #$0001,(-24540).W               ; $00F71A ; fade state 1?
        BEQ.W  .fade_state_1                    ; $00F720
        CMPI.W  #$0002,(-24540).W               ; $00F724 ; fade state 2?
        BEQ.W  .fade_state_2                    ; $00F72A
; --- Input: check both players for A/B/C or Start ---
        MOVE.W  (-14228).W,D1                   ; $00F72E ; P1 buttons
        ANDI.B  #$E0,D1                         ; $00F732 ; A/B/C mask
        BNE.S  .begin_fadeout                    ; $00F736 ; P1 action → exit
        MOVE.W  (-14226).W,D1                   ; $00F738 ; P2 buttons
        MOVE.W  D1,D2                           ; $00F73C
        ANDI.B  #$E0,D2                         ; $00F73E ; A/B/C mask
        BNE.S  .begin_fadeout                    ; $00F742 ; P2 action → exit
        ANDI.B  #$10,D1                         ; $00F744 ; P2 Start?
        BNE.S  .set_exit_flag                   ; $00F748
        MOVE.W  (-14228).W,D1                   ; $00F74A ; re-read P1
        ANDI.B  #$10,D1                         ; $00F74E ; P1 Start?
        BNE.S  .set_exit_flag                   ; $00F752
        SUBQ.W  #4,(-14210).W                   ; $00F754 ; tick timer
        BRA.W  .finish                          ; $00F758
.set_exit_flag:
        ST      (-24552).W                      ; $00F75C ; set exit flag
; --- Begin exit: save palettes based on panel config ---
.begin_fadeout:
        MOVE.B  #$A8,(-14172).W                 ; $00F760 ; SFX: confirm
        TST.B  (-24549).W                       ; $00F766 ; panel config
        BEQ.S  .save_palette_0                  ; $00F76A ; config 0
        CMPI.B  #$01,(-24549).W                 ; $00F76C ; config 1?
        BEQ.S  .save_palette_1                  ; $00F772
; config 2+: different palette mapping
        MOVE.B  (-24545).W,(-333).W             ; $00F774 ; pal → slot A
        MOVE.B  (-24544).W,(-337).W             ; $00F77A ; pal → slot B
        MOVE.B  (-24551).W,(-339).W             ; $00F780 ; pal → slot C
        BRA.W  .check_secondary_palette         ; $00F786
.save_palette_0:
        MOVE.B  (-24551).W,(-333).W             ; $00F78A ; pal → slot A
        MOVE.B  (-24544).W,(-337).W             ; $00F790 ; pal → slot B
        MOVE.B  (-24543).W,(-339).W             ; $00F796 ; pal → slot C
        BRA.S  .check_secondary_palette         ; $00F79C
.save_palette_1:
        MOVE.B  (-24545).W,(-333).W             ; $00F79E ; pal → slot A
        MOVE.B  (-24551).W,(-337).W             ; $00F7A4 ; pal → slot B
        MOVE.B  (-24543).W,(-339).W             ; $00F7AA ; pal → slot C
; --- Save secondary panel palette ---
.check_secondary_palette:
        CMPI.B  #$01,(-24548).W                 ; $00F7B0 ; secondary config
        BEQ.S  .save_secondary_1               ; $00F7B6
        MOVE.B  (-24542).W,(-336).W             ; $00F7B8 ; sec pal → slot D
        MOVE.B  (-24550).W,(-338).W             ; $00F7BE ; sec pal → slot E
        BRA.S  .finalize_fadeout                 ; $00F7C4
.save_secondary_1:
        MOVE.B  (-24550).W,(-336).W             ; $00F7C6 ; sec pal → slot D
        MOVE.B  (-24541).W,(-338).W             ; $00F7CC ; sec pal → slot E
; --- Trigger fade-out ---
.finalize_fadeout:
        CLR.B  (-24546).W                       ; $00F7D2 ; clear saved pal
        MOVE.B  #$01,(-14327).W                 ; $00F7D6 ; fade flag 1
        MOVE.B  #$01,(-14326).W                 ; $00F7DC ; fade flag 2
        BSET    #7,(-14322).W                   ; $00F7E2 ; trigger fade-out
        MOVE.B  #$01,(-14334).W                 ; $00F7E8 ; transition active
        MOVE.W  #$0002,(-24540).W               ; $00F7EE ; state → phase 2
        BRA.W  .dec_timer                        ; $00F7F4
; --- Fade state handlers (with COMM transfer) ---
.fade_state_1:
        bsr.w   comm_transfer_block     ; $6100 $033C ; SH2 COMM transfer
        BTST    #6,(-14322).W                   ; $00F7FC ; phase 1 done?
        BNE.S  .dec_timer                        ; $00F802 ; still fading
        CLR.W  (-24540).W                       ; $00F804 ; reset state
        BRA.W  .dec_timer                        ; $00F808
.fade_state_2:
        bsr.w   comm_transfer_block     ; $6100 $0328 ; SH2 COMM transfer
        BTST    #7,(-14322).W                   ; $00F810 ; phase 2 done?
        BNE.S  .dec_timer                        ; $00F816 ; still fading
        CLR.W  (-24540).W                       ; $00F818 ; reset state
        ADDQ.W  #4,(-14210).W                   ; $00F81C ; advance scene
        BRA.W  .finish                        ; $00F820
.dec_timer:
        SUBQ.W  #4,(-14210).W                   ; $00F824 ; tick timer
; --- Frame end ---
.finish:
        MOVE.W  #$0018,$00FF0008                ; $00F828 ; V-INT period = 24
        MOVE.B  #$01,(-14303).W                 ; $00F830 ; frame ready flag
        RTS                                     ; $00F836
