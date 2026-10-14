; ============================================================================
; entity_render_frame_orch ($00617A-$0061FE) — Entity Render Frame Orchestrator
; ============================================================================
; CODE: 134 bytes — entity field clears, 21 BSR calls, flag tests
; Called after entity_render_pipeline_with_vdp_dma; orchestrates per-frame
; entity rendering by testing flags, clearing fields, and dispatching to
; 21 subsystems via BSR.
; ============================================================================
entity_render_frame_orch:
        btst    #0,($FFFFC80E).w                ; $00617A  scene flag bit 0 set?
        bne.w   entity_render_pipeline_with_vdp_dma_2p_copy+24 ; $006180  yes → skip to 2P pipeline
        move.b  #$01,($FFFFC800).w              ; $006184  mark scene active
        moveq   #0,D0                           ; $00618A  clear D0
        move.w  D0,$0044(A0)                    ; $00618C  clear display_offset
        move.w  D0,$0046(A0)                    ; $006190  clear display_scale
        move.w  D0,$004A(A0)                    ; $006194  clear display_aux
        jsr     field_check_guard(pc)           ; $006198  $0080CC
        jsr     timer_decrement_multi(pc)       ; $00619C  $008548
        jsr     suspension_steering_damping(pc) ; $0061A0  $009802
        jsr     object_anim_timer_speed_clear+6(pc) ; $0061A4  $007E7A
        jsr     entity_pos_update(pc)           ; $0061A8  $006F98
        jsr     multi_flag_test(pc)             ; $0061AC  $007CD8
        jsr     angle_to_sine(pc)               ; $0061B0  $0070AA
        jsr     object_link_copy_table_lookup(pc) ; $0061B4  $00714A
        jsr     rotational_offset_calc(pc)      ; $0061B8  $00764E
        jsr     position_threshold_check(pc)    ; $0061BC  $007F50
        jsr     race_pos_sorting_and_rank_assignment+50(pc) ; $0061C0  $009CCE
        jsr     effect_countdown(pc)            ; $0061C4  $00AC3E
        jsr     set_camera_regs_to_invalid(pc)  ; $0061C8  $009B54
        jsr     proximity_zone_multi(pc)        ; $0061CC  $0086C8
        jsr     vdp_buffer_xfer_camera_offset_apply(pc) ; $0061D0  $003126
        jsr     vdp_config_xfer_scaled_params(pc) ; $0061D4  $003160
        jsr     conditional_object_velocity_negate(pc) ; $0061D8  $007624
        jsr     object_geometry_visibility_collect(pc) ; $0061DC  $00734E
        jsr     object_table_sprite_param_update(pc) ; $0061E0  $0036DE
        jsr     object_proximity_check_jump_table_dispatch(pc) ; $0061E4  $0037B6
        jsr     render_slot_setup+88(pc)        ; $0061E8  $003F86
        jsr     scroll_pan_calc_vdp_write(pc)   ; $0061EC  $009064
        move.b  ($FFFFC304).w,($FFFFC30C).w    ; $0061F0  copy render flags
        move.w  ($FFFFC8A0).w,D0                ; $0061F6  D0 = frame counter
        btst    #7,($FFFFC81C).w                ; $0061FA  bit 7 control flag set?
