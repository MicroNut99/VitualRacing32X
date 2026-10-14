; ============================================================================
; Scene State Dispatcher with Track Data Tables
; ROM Range: $0129E0-$012A72 (146 bytes)
; ============================================================================
;
; PURPOSE
; -------
; Contains three 16-word track-specific data tables followed by a scene
; state dispatcher. The dispatcher calls sound_command_dispatch_sound_driver_call for setup, then
; jumps to a handler based on the game state index at $C87E. A separate
; entry point handles post-dispatch completion: updates objects, checks
; display bit 6, and advances the state machine.
;
; DATA TABLES
; -----------
;   3 tables x 16 words each (96 bytes total)
;   $7FFF / $FFFF used as sentinel values for unused entries
;
; MEMORY VARIABLES
; ----------------
;   $FFFFC87E  Game state index (word, used as jump table offset)
;   $FFFFC80E  Display control flags (bit 6 tested)
;
; Entry: scene_state_disp_track_data_tables -> data tables (not executed directly)
;        fn_12200_023_dispatch -> scene state dispatcher
;        fn_12200_023_complete -> post-dispatch completion check
; Calls:
;   sound_command_dispatch_sound_driver_call: scene setup
;   object_update: object system update
; Jump table targets:
;   State 0:  camera_demo_palette_sh2_setup
;   State 4:  fn_12200_025_exec (mid-function DMA entry)
;   State 8:  camera_selection_main_loop
;   State 12: sh2_mode_disp_select_scene_by_track_mode
; Uses: D0, A1
; ============================================================================

; --- Track data table 1 (16 words: per-track parameter values, DATA) ---
scene_state_disp_track_data_tables:
        dc.w    $5AD4                           ; $0129E0: track 0
        dc.w    $5AD6                           ; $0129E2: track 1
        dc.w    $7FFF                           ; $0129E4: sentinel (unused)
        dc.w    $7FFF                           ; $0129E6: sentinel (unused)
        dc.w    $52B0                           ; $0129E8: track 4
        dc.w    $52B1                           ; $0129EA: track 5
        dc.w    $56D2                           ; $0129EC: track 6
        dc.w    $5AD3                           ; $0129EE: track 7
        dc.w    $5EF4                           ; $0129F0: track 8
        dc.w    $2964                           ; $0129F2: track 9
        dc.w    $7FFF                           ; $0129F4: sentinel (unused)
        dc.w    $7FFF                           ; $0129F6: sentinel (unused)
        dc.w    $7FFF                           ; $0129F8: sentinel (unused)
        dc.w    $7FFF                           ; $0129FA: sentinel (unused)
        dc.w    $7FFF                           ; $0129FC: sentinel (unused)
        dc.w    $7FFF                           ; $0129FE: sentinel (unused)
; --- Track data table 2 (16 words: per-track parameter values, DATA) ---
        dc.w    $6B58                           ; $012A00: track 0
        dc.w    $6737                           ; $012A02: track 1
        dc.w    $7FFF                           ; $012A04: sentinel (unused)
        dc.w    $7FFF                           ; $012A06: sentinel (unused)
        dc.w    $5A92                           ; $012A08: track 4
        dc.w    $5ED4                           ; $012A0A: track 5
        dc.w    $6716                           ; $012A0C: track 6
        dc.w    $6B58                           ; $012A0E: track 7
        dc.w    $739A                           ; $012A10: track 8
        dc.w    $61E8                           ; $012A12: track 9
        dc.w    $7FFF                           ; $012A14: sentinel (unused)
        dc.w    $7FFF                           ; $012A16: sentinel (unused)
        dc.w    $7FFF                           ; $012A18: sentinel (unused)
        dc.w    $7FFF                           ; $012A1A: sentinel (unused)
        dc.w    $7FFF                           ; $012A1C: sentinel (unused)
        dc.w    $7FFF                           ; $012A1E: sentinel (unused)
; --- Track data table 3 (16 words: signed per-track offsets, $FFFF sentinel, DATA) ---
        dc.w    $FFBC                           ; $012A20: track 0 (-68)
        dc.w    $FF7A                           ; $012A22: track 1 (-134)
        dc.w    $FFFF                           ; $012A24: sentinel (unused)
        dc.w    $FFFF                           ; $012A26: sentinel (unused)
        dc.w    $C445                           ; $012A28: track 4 (-15291)
        dc.w    $D12B                           ; $012A2A: track 5 (-11989)
        dc.w    $E212                           ; $012A2C: track 6 (-7662)
        dc.w    $EEF8                           ; $012A2E: track 7 (-4360)
        dc.w    $FFFF                           ; $012A30: sentinel (unused)
        dc.w    $831F                           ; $012A32: track 9 (-31969)
        dc.w    $FFFF                           ; $012A34: sentinel (unused)
        dc.w    $FFFF                           ; $012A36: sentinel (unused)
        dc.w    $FFFF                           ; $012A38: sentinel (unused)
        dc.w    $FFFF                           ; $012A3A: sentinel (unused)
        dc.w    $FFFF                           ; $012A3C: sentinel (unused)
        dc.w    $FFFF                           ; $012A3E: sentinel (unused)

; --- Scene state dispatcher ---
fn_12200_023_dispatch:
        dc.w    $4EB9                           ; $012A40: JSR (abs.L)
        dc.l    sound_command_dispatch_sound_driver_call+$00880000 ; -> sound setup
        move.w  ($FFFFC87E).w,d0               ; $012A46: load game state index
        movea.l .jump_table(pc,d0.w),a1        ; $012A4A: read target address
        jmp     (a1)                            ; $012A4E: dispatch to handler
.jump_table:
        dc.l    camera_demo_palette_sh2_setup+$00880000          ; $012A50: state 0
        dc.l    fn_12200_025_exec+$00880000     ; $012A54: state 4
        dc.l    camera_selection_main_loop+$00880000          ; $012A58: state 8
        dc.l    sh2_mode_disp_select_scene_by_track_mode+$00880000          ; $012A5C: state 12

; --- Post-dispatch completion check ---
fn_12200_023_complete:
        jsr     object_update(pc)              ; $012A60: update objects
        btst    #6,($FFFFC80E).w               ; $012A64: display complete?
        bne.s   .done                           ; $012A6A: no: skip advance
        addq.w  #4,($FFFFC87E).w               ; $012A6C: advance state machine
.done:
        rts                                     ; $012A70
