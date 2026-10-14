; ============================================================================
; race_scene_init_vdp_mode — Race Scene Init (VDP Mode Handler)
; ROM Range: $00C0F0-$00C1FE (272 bytes)
; ============================================================================
; Major scene initialization function for race/3D mode. Disables interrupts,
; configures VDP hardware, sets up COMM registers, calls multiple subsystems,
; loads ROM tables, and initializes state variables.
;
; Falls through to scene_init_orch at $C200 (no RTS in this block).
;
; Entry: Called as scene handler when VDP flag ($FEB7) bit 7 is set.
;        Pointer $0088C0F0 stored at $FF0002.
; Uses: D0-D1, A0, A2
; ============================================================================

race_scene_init_vdp_mode:
        move.w  #$2700,sr                       ; $00C0F0  disable interrupts
        bclr    #6,($FFFFC875).w                ; $00C0F4  clear bit 6 of VDP flag
        move.w  ($FFFFC874).w,(a5)              ; $00C0FA  load VDP state word into (A5)
        move.w  #$0083,($00A15100).l            ; $00C0FE  MARS adapter ctrl
        andi.b  #$FC,($00A15181).l              ; $00C106  clear low 2 bits of MARS status
        jsr     $0088270A                       ; $00C10E  hardware setup
        move.b  #$01,($FFFFC80D).w              ; $00C114  set display enable flag
        andi.b  #$09,($FFFFC80E).w              ; $00C11A  mask display flags to bits 0+3
        bset    #3,($FFFFC80E).w                ; $00C120  set display flag bit 3
        moveq   #0,d0                           ; $00C126  D0 = 0
        moveq   #0,d1                           ; $00C128  D1 = 0
        move.b  #$00,d0                         ; $00C12A  game mode → D0
        move.b  #$00,d1                         ; $00C12E  track number → D1
        jsr     game_mode_track_config(pc)      ; $00C132  configure mode/track indices
        move.b  ($FFFFC8C9).w,d0                ; $00C136  load track sub-index
        addq.b  #1,d0                           ; $00C13A  increment
        move.b  d0,($00A15122).l                ; $00C13C  → COMM1 register
        move.w  #$0103,($FFFFC8A8).w            ; $00C142  set SH2 command word
        move.b  ($FFFFC8A9).w,($00A15121).l     ; $00C148  low byte → COMM0_LO
        move.b  ($FFFFC8A8).w,($00A15120).l     ; $00C150  high byte → COMM0_HI
        move.b  #$00,($FFFFC80F).w              ; $00C158  clear display sub-flag
        move.w  #$0000,($FFFFC8BC).w            ; $00C15E  clear race timer
        jsr     $0088D1D4                       ; $00C164  subsystem init A
        jsr     $0088D42C                       ; $00C16A  subsystem init B
        lea     $008BA220,a0                    ; $00C170  ROM pointer table A
        move.w  ($FFFFC8A0).w,d0                ; $00C176  game mode × 4
        movea.l $00(a0,d0.w),a2                 ; $00C17A  A2 = table[mode]
        jsr     $0088284C                       ; $00C17E  data loader A
        lea     $008BAE38,a0                    ; $00C184  ROM pointer table B
        move.w  ($FFFFC8CC).w,d0                ; $00C18A  race substate × 4
        movea.l $00(a0,d0.w),a2                 ; $00C18E  A2 = table[substate]
        jsr     $00882862                       ; $00C192  data loader B
        move.w  #$0010,($00FF0008).l            ; $00C198  set display mode
        move.w  #$0000,($FFFFC8AA).w            ; $00C1A0  clear scene state
        jsr     $008849AA                       ; $00C1A6  SH2 scene init
        jsr     scene_init_sh2_buffer_clear_loop(pc) ; $00C1AC  SH2 buffer clear + state init
        move.b  #$00,($FFFFC314).w              ; $00C1B0  clear collision flag
        btst    #0,($FFFFC818).w                ; $00C1B6  test race mode bit
        beq.s   .skip_collision_set             ; $00C1BC  if clear → skip
        move.b  #$01,($FFFFC314).w              ; $00C1BE  set collision flag
.skip_collision_set:
        moveq   #0,d0                           ; $00C1C4
        jsr     scene_camera_init(pc)            ; $00C1C6  camera segment data copy
        jsr     track_graphics_and_sound_loader+$AE(pc) ; $00C1CA  track gfx/sound (2nd entry)
        jsr     vdp_load_table_b(pc)            ; $00C1CE  load VDP register table B
        jsr     scene_init_vdp_block_setup_counter_reset+$36(pc) ; $00C1D2  counter init (2nd entry)
        move.b  #$05,($FFFFC310).w              ; $00C1D6  set state phase = 5
        move.b  #$00,($FFFFC30F).w              ; $00C1DC  clear animation state
        lea     ($FFFF9000).w,a0                ; $00C1E2  object table base
        jsr     scene_camera_init+$1E(pc)       ; $00C1E6  camera setup (main entry, A0=objects)
        moveq   #0,d1                           ; $00C1EA  D1 = 0
        jsr     object_entries_reset_init_fixed_table(pc) ; $00C1EC  reset 16 object entries
        jsr     object_table_init_entry_array(pc) ; $00C1F0  init 15-entry object table
        jsr     $0088A80A                       ; $00C1F4  entity_table_load_mode
        jsr     $0088A144                       ; $00C1FA  entity init
; --- falls through to scene_init_orch at $C200 ---
