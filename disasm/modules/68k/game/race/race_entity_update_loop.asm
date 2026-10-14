; ============================================================================
; race_entity_update_loop — Race Entity Update Loop
; ROM Range: $00593C-$005AB6 (378 bytes)
; Per-frame update for race entities. Selects from two 10-entry jump tables
; (normal vs special mode, selected by bit 3 of $C88E). Executes
; movement calculation, speed, collision avoidance, heading update, and
; lateral/longitudinal force computation using sine lookup tables.
;
; Entry: A0 = entity base pointer
; Uses: D0, D1, D7, A0, A1, A2, A4, A6
; RAM: $9F00 obj_table_3, $C89C sh2_comm_state
; Object fields: +$02 flags, +$04 speed, +$18 position, +$24/+$26 heading,
;   +$2C lap counter, +$32 angle, +$3A/+$3E lateral/longitudinal force,
;   +$46 tilt, +$54 collision flags, +$6A lock, +$C6/+$C8 angles
; Confidence: high
; ============================================================================

race_entity_update_loop:
        LEA     (-24576).W,A4                   ; $00593C
        MOVE.W  (-15764).W,D0                   ; $005940
        BTST    #7,(-14308).W                   ; $005944
        BNE.S  .has_special_flags                        ; $00594A
        TST.W  (-14180).W                       ; $00594C
.check_race_state:
        BEQ.S  .no_special_flags                ; $005950
.has_special_flags:
        ANDI.W  #$0138,D0                       ; $005952
        BEQ.S  .update_secondary_entity         ; $005956
        BRA.S  .begin_primary_update            ; $005958
.no_special_flags:
        ANDI.W  #$0130,D0                       ; $00595A
        BEQ.S  .update_secondary_entity         ; $00595E
        BRA.S  .begin_primary_update            ; $005960
.update_secondary_entity:
        LEA     (-24832).W,A0                   ; $005962
        jsr     race_entity_update_loop+176(pc); $4EBA $0084
.begin_primary_update:
        LEA     (-28672).W,A0                   ; $00596A
        MOVE.L  $00B2(A0),$0018(A0)             ; $00596E
        MOVE.B  $00E5(A0),D1                    ; $005974
.check_ai_flags:
        ANDI.B  #$06,D1                         ; $005978
        BEQ.S  .use_current_position                        ; $00597C
        MOVE.L  (-14580).W,$0018(A0)            ; $00597E
.use_current_position:
        MOVE.W  (-16262).W,D0                   ; $005984
        BTST    #3,(-14322).W                   ; $005988
        BNE.S  .use_special_table                        ; $00598E
        MOVEA.L .normal_table(PC,D0.W),A1       ; $005990
        JMP     (A1)                            ; $005994
.use_special_table:
        MOVEA.L .special_table(PC,D0.W),A1      ; $005996
        JMP     (A1)                            ; $00599A
; --- Normal render pipeline jump table (10 entries at $00599C) ---
; Selected when bit 3 of $C88E is clear. Index D0 from $C08A (0/4/8/.../36).
.normal_table:
        dc.l    $00885AB6               ; [0] entity_render_pipeline (A: full)
        dc.l    $00885B6E               ; [1] entity_render_pipeline (B: reduced)
        dc.l    $00885BE0               ; [2] entity_render_pipeline (C: countdown)
        dc.l    $00885C5A               ; [3] entity_render_pipeline (D: minimal)
        dc.l    $00885D08               ; [4] player_entity_frame_update
        dc.l    $00885DE0               ; [5] entity_data_table_render_pipeline_variant+24
        dc.l    $00885E38               ; [6] game_frame_orch
        dc.l    $00886394               ; [7] 2p_copy (D: MOVEM block copy)
        dc.l    $0088633A               ; [8] 2p_copy (C: stripped)
        dc.l    $00885BEC               ; [9] entity_render_pipeline (C: skip init)
; --- Special render pipeline jump table (10 entries at $0059C4) ---
; Selected when bit 3 of $C88E is set. Same index scheme.
.special_table:
        dc.l    $00885EEA               ; [0] vdp_dma variant (A: full)
        dc.l    $00885F9A               ; [1] vdp_dma variant (B: reduced)
        dc.l    $00886008               ; [2] vdp_dma variant (C: countdown)
        dc.l    $008860D4               ; [3] vdp_dma variant (D: display-only)
        dc.l    $0088617A               ; [4] entity_render_frame_orch
        dc.l    $00885DE0               ; [5] entity_data_table_render_pipeline_variant+24
        dc.l    $00886292               ; [6] 2p_copy (B: full + VDP DMA)
        dc.l    $00886394               ; [7] 2p_copy (D: MOVEM block copy)
        dc.l    $0088633A               ; [8] 2p_copy (C: stripped)
        dc.l    $00886014               ; [9] vdp_dma variant (C: skip init)
        MOVE.W  D7,-(A7)                        ; $0059EC
        jsr     entity_speed_clamp(pc)  ; $4EBA $4122
        jsr     speed_calculation(pc)   ; $4EBA $49C6
        jsr     speed_interpolation(pc) ; $4EBA $49F2
.post_speed_calc:
        jsr     collision_avoidance_speed_calc(pc); $4EBA $4A74
        MOVE.W  $0054(A0),D0                    ; $0059FE
        ANDI.W  #$0009,D0                       ; $005A02
        BEQ.S  .skip_collision_flag                        ; $005A06
        TST.W  $006A(A0)                        ; $005A08
        BNE.S  .skip_collision_flag                        ; $005A0C
        CMPI.W  #$0064,$0004(A0)                ; $005A0E
        BLE.S  .skip_collision_flag                        ; $005A14
        ORI.W  #$1000,$0002(A0)                 ; $005A16
.skip_collision_flag:
        jsr     effect_timer_mgmt(pc)   ; $4EBA $4932
        TST.W  $0004(A0)                        ; $005A20
        BEQ.S  .skip_decel                        ; $005A24
        SUBI.W  #$2000,$00BC(A0)                ; $005A26
        SUBI.W  #$1800,$00C4(A0)                ; $005A2C
.skip_decel:
        jsr     entity_heading_init+4(pc); $4EBA $2082
        LEA     $0093AC2C,A1                    ; $005A36
        MOVE.W  $00C8(A0),D0                    ; $005A3C
        SUB.W  $0032(A0),D0                     ; $005A40
        ADD.W   D0,D0                           ; $005A44
        BMI.S  .angle_negative                        ; $005A46
        ANDI.W  #$03FF,D0                       ; $005A48
        MOVE.W  $00(A1,D0.W),D0                 ; $005A4C
        BRA.S  .store_lateral_force                        ; $005A50
.angle_negative:
        NEG.W  D0                               ; $005A52
        ANDI.W  #$03FF,D0                       ; $005A54
        MOVE.W  $00(A1,D0.W),D0                 ; $005A58
        NEG.W  D0                               ; $005A5C
.store_lateral_force:
        MOVE.W  D0,$003A(A0)                    ; $005A5E
        LEA     $0093A82C,A1                    ; $005A62
        MOVE.W  $0032(A0),D0                    ; $005A68
        SUB.W  $00C6(A0),D0                     ; $005A6C
        ADD.W   D0,D0                           ; $005A70
        BMI.S  .long_angle_negative                        ; $005A72
        ANDI.W  #$03FF,D0                       ; $005A74
        MOVE.W  $00(A1,D0.W),D0                 ; $005A78
        BRA.S  .store_longitudinal_force                        ; $005A7C
.long_angle_negative:
        NEG.W  D0                               ; $005A7E
        ANDI.W  #$03FF,D0                       ; $005A80
        MOVE.W  $00(A1,D0.W),D0                 ; $005A84
        NEG.W  D0                               ; $005A88
.store_longitudinal_force:
        MOVE.W  D0,$003E(A0)                    ; $005A8A
        MOVE.W  $006E(A0),$0046(A0)             ; $005A8E
        jsr     rotational_offset_calc(pc); $4EBA $1BB8
        jsr     object_link_copy_table_lookup(pc); $4EBA $16B0
        MOVE.W  $0026(A0),D0                    ; $005A9C
        SUB.W  $0024(A0),D0                     ; $005AA0
        CMPI.W  #$0064,D0                       ; $005AA4
        BLT.S  .skip_lap_increment                        ; $005AA8
        ADDQ.W  #1,$002C(A0)                    ; $005AAA
.skip_lap_increment:
        LEA     $0100(A0),A0                    ; $005AAE
        MOVE.W  (A7)+,D7                        ; $005AB2
        RTS                                     ; $005AB4
