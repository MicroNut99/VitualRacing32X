; ============================================================================
; camera_selection_main_loop — Camera Selection Main Loop
; ROM Range: $012CC2-$012F0A (584 bytes)
; ============================================================================
; Per-frame update for the camera selection screen. Handles:
;   1. DMA transfer, object_update, sprite_update
;   2. Render main camera view ($06038000) and overlay ($0603DE80)
;   3. Camera selection via D-pad up/down (cycles through 6 cameras,
;      with skip logic for locked camera positions via bit 3 of $C958)
;   4. Optional replay mode toggle via left/right (with smooth scrolling)
;   5. Confirm selection (A button → state $0002), cancel (Start → exit)
;   6. State machine: browsing ($0000), confirming ($0001/$0002)
;
; Uses: D0, D1, D2, A0, A1
; RAM:
;   $C87E: game_state
; Calls:
;   $00B684: object_update
;   $00B6DA: sprite_update
;   $00E35A: sh2_send_cmd
;   $00E52C: dma_transfer
; ============================================================================

; --- Per-frame init: memory, objects, sprites ---
camera_selection_main_loop:
        CLR.W  D0                               ; $012CC2
        bsr.w   MemoryInit              ; $6100 $B866
        jsr     object_update(pc)       ; $4EBA $89BA
        jsr     animated_seq_player+10(pc); $4EBA $8A0C
        JSR     $0088179E                       ; $012CD0
; --- State machine dispatch ---
        TST.W  (-24518).W                       ; $012CD6 ; anim state
        BNE.W  .render_main_view                ; $012CDA ; animating, skip input
        TST.B  (-14309).W                       ; $012CDE ; confirm mode flag
        BNE.W  .confirm_mode                    ; $012CE2
; --- D-pad camera cycling (6 cameras: 0-5) ---
        MOVE.B  (-24551).W,D0                   ; $012CE6 ; current cam index
        MOVE.W  (-14228).W,D1                   ; $012CEA ; P1 buttons
        TST.L  (-24540).W                       ; $012CEE ; scroll in progress?
        BNE.W  .store_cam_index                 ; $012CF2
; --- D-pad UP: next camera ---
        BTST    #3,D1                           ; $012CF6 ; UP pressed?
        BEQ.S  .check_down                      ; $012CFA
        MOVE.B  #$A9,(-14172).W                 ; $012CFC ; SFX: cursor move
        TST.B  (-600).W                         ; $012D02 ; replay mode enabled?
        BEQ.S  .no_replay_up                    ; $012D06
        CMPI.B  #$05,D0                         ; $012D08 ; at last cam (replay)?
        BLT.S  .next_cam_up                     ; $012D0C
        CLR.B  D0                               ; $012D0E ; wrap to 0
        MOVE.L  #$00000004,(-24540).W           ; $012D10 ; scroll right +4
        MOVE.W  #$0037,(-24536).W               ; $012D18 ; scroll duration
        BRA.W  .store_cam_index                 ; $012D1E
.next_cam_up:
        ADDQ.B  #1,D0                           ; $012D22
        BTST    #3,(-14312).W                   ; $012D24 ; cam 2 locked? (bit 3)
        BEQ.S  .skip_locked_up                  ; $012D2A
        CMPI.B  #$02,D0                         ; $012D2C ; skip cam 2
        BNE.S  .skip_locked_up                  ; $012D30
        MOVE.B  #$03,D0                         ; $012D32 ; jump to cam 3
.skip_locked_up:
        CMPI.B  #$05,D0                         ; $012D36 ; wrapped to replay?
        BNE.W  .store_cam_index                 ; $012D3A
        MOVE.L  #$FFFFFFFC,(-24540).W           ; $012D3E ; scroll left -4
        MOVE.W  #$0037,(-24536).W               ; $012D46 ; scroll duration
        BRA.W  .store_cam_index                 ; $012D4C
; --- UP without replay mode (cams 0-4) ---
.no_replay_up:
        CMPI.B  #$04,D0                         ; $012D50 ; at last non-replay?
        BLT.S  .next_cam_up_no_replay           ; $012D54
        CLR.B  D0                               ; $012D56 ; wrap to 0
        BRA.W  .store_cam_index                 ; $012D58
.next_cam_up_no_replay:
        ADDQ.B  #1,D0                           ; $012D5C
        BTST    #3,(-14312).W                   ; $012D5E ; cam 2 locked?
        BEQ.S  .skip_locked_up_no_replay        ; $012D64
        CMPI.B  #$02,D0                         ; $012D66
        BNE.S  .skip_locked_up_no_replay        ; $012D6A
        MOVE.B  #$03,D0                         ; $012D6C ; skip cam 2 → 3
.skip_locked_up_no_replay:
        BRA.W  .store_cam_index                 ; $012D70
; --- D-pad DOWN: previous camera ---
.check_down:
        BTST    #2,D1                           ; $012D74 ; DOWN pressed?
        BEQ.W  .store_cam_index                 ; $012D78
        MOVE.B  #$A9,(-14172).W                 ; $012D7C ; SFX: cursor move
        TST.B  D0                               ; $012D82 ; at cam 0?
        BGT.S  .prev_cam_down                   ; $012D84
        MOVE.B  #$04,D0                         ; $012D86 ; wrap to last
        TST.B  (-600).W                         ; $012D8A ; replay available?
        BEQ.W  .store_cam_index                 ; $012D8E
        MOVE.B  #$05,D0                         ; $012D92 ; wrap to replay cam
        MOVE.L  #$FFFFFFFC,(-24540).W           ; $012D96 ; scroll left
        MOVE.W  #$0037,(-24536).W               ; $012D9E ; scroll duration
        BRA.W  .store_cam_index                 ; $012DA4
.prev_cam_down:
        SUBQ.B  #1,D0                           ; $012DA8
        BTST    #3,(-14312).W                   ; $012DAA ; cam 2 locked?
        BEQ.S  .skip_locked_down                ; $012DB0
        CMPI.B  #$02,D0                         ; $012DB2
        BNE.S  .skip_locked_down                ; $012DB6
        MOVE.B  #$01,D0                         ; $012DB8 ; skip cam 2 → 1
.skip_locked_down:
        TST.B  (-600).W                         ; $012DBC ; replay mode?
        BEQ.W  .store_cam_index                 ; $012DC0
        CMPI.B  #$04,D0                         ; $012DC4 ; at replay boundary?
        BNE.W  .store_cam_index                 ; $012DC8
        MOVE.L  #$00000004,(-24540).W           ; $012DCC ; scroll right
        MOVE.W  #$0037,(-24536).W               ; $012DD4 ; scroll duration
        BRA.W  .store_cam_index                 ; $012DDA
; --- Confirm mode: toggle between cam 2 and cam 4 ---
.confirm_mode:
        MOVE.B  (-24551).W,D0                   ; $012DDE ; current cam index
        MOVE.W  (-14226).W,D1                   ; $012DE2 ; P2 buttons
        BTST    #3,D1                           ; $012DE6 ; UP?
        BNE.S  .toggle_confirm                  ; $012DEA
        BTST    #2,D1                           ; $012DEC ; DOWN?
        BNE.S  .toggle_confirm                  ; $012DF0
        BRA.W  .store_cam_index                 ; $012DF2 ; no input
.toggle_confirm:
        MOVE.B  #$A9,(-14172).W                 ; $012DF6 ; SFX: cursor
        CMPI.B  #$02,D0                         ; $012DFC ; currently cam 2?
        BEQ.S  .set_cam_4                       ; $012E00
        MOVE.B  #$02,D0                         ; $012E02 ; switch to cam 2
        BRA.W  .store_cam_index                 ; $012E06
.set_cam_4:
        MOVE.B  #$04,D0                         ; $012E0A ; switch to cam 4
.store_cam_index:
        MOVE.B  D0,(-24551).W                   ; $012E0E ; save selection
; --- Render main 3D camera view via SH2 ---
.render_main_view:
        MOVEA.L #$06038000,A0                   ; $012E12 ; SH2 SDRAM src
        MOVEA.L #$04014000,A1                   ; $012E18 ; frame buffer dst
        ADDA.L  (-24544).W,A1                   ; $012E1E ; + scroll offset
        MOVE.W  #$0150,D0                       ; $012E22 ; width = 336
        MOVE.W  #$0048,D1                       ; $012E26 ; height = 72
        DC.W    $4EBA,$B52E         ; JSR     $00E35A(PC); $012E2A ; sh2_send_cmd
        TST.L  (-24540).W                       ; $012E2E ; scrolling active?
        BNE.W  .render_overlay                  ; $012E32 ; skip cmd_27
.wait_comm_ready:
        TST.B  COMM0_HI                        ; $012E36 ; SH2 busy?
        BNE.S  .wait_comm_ready                 ; $012E3C
        bsr.w   camera_sh2_command_27_dispatch+28; $6100 $0132 ; tile update
; --- Render UI overlay panel ---
.render_overlay:
        MOVEA.L #$0603DE80,A0                   ; $012E42 ; overlay src
        MOVEA.L #$04004C60,A1                   ; $012E48 ; overlay dst
        MOVE.W  #$0080,D0                       ; $012E4E ; width = 128
        MOVE.W  #$0010,D1                       ; $012E52 ; height = 16
        DC.W    $4EBA,$B502         ; JSR     $00E35A(PC); $012E56 ; sh2_send_cmd
.wait_comm_ready_2:
        TST.B  COMM0_HI                        ; $012E5A ; SH2 busy?
        BNE.S  .wait_comm_ready_2               ; $012E60
; --- Button detection: confirm/cancel ---
        TST.L  (-24540).W                       ; $012E62 ; scrolling?
        BNE.W  .no_action_buttons               ; $012E66 ; ignore buttons
        CMPI.W  #$0001,(-24518).W               ; $012E6A ; anim phase 1?
        BEQ.W  .wait_anim_phase1                ; $012E70
        CMPI.W  #$0002,(-24518).W               ; $012E74 ; anim phase 2?
        BEQ.W  .wait_anim_phase2                ; $012E7A
        MOVE.W  (-14228).W,D1                   ; $012E7E ; P1 buttons
        TST.B  (-14309).W                       ; $012E82 ; confirm active?
        BEQ.W  .get_buttons                     ; $012E86
        MOVE.W  (-14226).W,D1                   ; $012E8A ; use P2 buttons
.get_buttons:
        MOVE.W  D1,D2                           ; $012E8E
        ANDI.B  #$E0,D2                         ; $012E90 ; A/B/C mask
        BNE.S  .check_start                     ; $012E94 ; action pressed
.no_action_buttons:
        SUBQ.W  #8,(-14210).W                   ; $012E96 ; decrement timer
        BRA.W  .frame_end                       ; $012E9A
.check_start:
        BTST    #0,D1                           ; $012E9E ; Start button?
        BEQ.S  .setup_confirm                   ; $012EA2
        BSET    #0,(-14325).W                   ; $012EA4 ; mark Start pressed
; --- Begin exit transition ---
.setup_confirm:
        MOVE.B  #$A8,(-14172).W                 ; $012EAA ; SFX: confirm
        MOVE.B  #$01,(-14327).W                 ; $012EB0 ; fade flag 1
        MOVE.B  #$01,(-14326).W                 ; $012EB6 ; fade flag 2
        BSET    #7,(-14322).W                   ; $012EBC ; trigger fade-out
        MOVE.B  #$01,(-14334).W                 ; $012EC2 ; transition active
        MOVE.W  #$0002,(-24518).W               ; $012EC8 ; state → phase 2
        BRA.W  .scroll_left                     ; $012ECE
; --- Wait for animation phases to complete ---
.wait_anim_phase1:
        BTST    #6,(-14322).W                   ; $012ED2 ; phase 1 done?
        BNE.S  .scroll_left                     ; $012ED8 ; still fading
        CLR.W  (-24518).W                       ; $012EDA ; reset state
        BRA.W  .scroll_left                     ; $012EDE
.wait_anim_phase2:
        BTST    #7,(-14322).W                   ; $012EE2 ; phase 2 done?
        BNE.S  .scroll_left                     ; $012EE8 ; still fading
        CLR.W  (-24518).W                       ; $012EEA ; reset state
        ADDQ.W  #4,(-14210).W                   ; $012EEE ; advance scene timer
        BRA.W  .frame_end                       ; $012EF2
.scroll_left:
        SUBQ.W  #8,(-14210).W                   ; $012EF6 ; scroll timer--
; --- Frame end: set V-INT timing ---
.frame_end:
        MOVE.W  #$0018,$00FF0008                ; $012EFA ; V-INT period = 24
        MOVE.B  #$01,(-14303).W                 ; $012F02 ; frame ready flag
        RTS                                     ; $012F08
