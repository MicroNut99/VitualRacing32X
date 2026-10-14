; ============================================================================
; Camera State Dispatcher (Data Prefix + Jump Table)
; ROM Range: $013292-$013346 (180 bytes)
; ============================================================================
; Category: game
; Purpose: Data prefix (128 bytes of object/sprite descriptors) +
;   state dispatcher. Calls initialization ($00882080), then reads
;   game_state ($C87E) to index a 3-entry PC-relative jump table:
;     State 0 -> $00893346 (camera_render_dma_overlay)
;     State 4 -> $008934F0 (camera_menu_orch+$28)
;     State 8 -> $00893824 (sh2_scene_reset_cond_handler_by_player_2_flag)
;   After dispatch returns: calls object_update, checks display bit 6,
;   advances game_state if clear, then SH2 scene transition.
;
; Uses: D0, D4, A0, A1
; RAM:
;   $C87E: game_state (word)
;   $C80E: display control (byte, bit 6 checked)
; Calls:
;   $00B684: object_update
;   $00882080: initialization
;   $0088205E: SH2 scene transition
; ============================================================================

camera_state_disp:
; --- data prefix: 12 max-value sentinels (DATA) ---
        dc.w    $7FFF                           ; $013292
        dc.w    $7FFF                           ; $013294
        dc.w    $7FFF                           ; $013296
        dc.w    $7FFF                           ; $013298
        dc.w    $7FFF                           ; $01329A
        dc.w    $7FFF                           ; $01329C
        dc.w    $7FFF                           ; $01329E
        dc.w    $7FFF                           ; $0132A0
        dc.w    $7FFF                           ; $0132A2
        dc.w    $7FFF                           ; $0132A4
        dc.w    $7FFF                           ; $0132A6
        dc.w    $7FFF                           ; $0132A8
; --- 5 identical descriptor entries (4 words each, DATA) ---
        dc.w    $4DC8,$520B,$5A6E,$62D1         ; $0132AA  entry[0]
        dc.w    $4DC8,$520B,$5A6E,$62D1         ; $0132B2  entry[1]
        dc.w    $4DC8,$520B,$5A6E,$62D1         ; $0132BA  entry[2]
        dc.w    $4DC8,$520B,$5A6E,$62D1         ; $0132C2  entry[3]
        dc.w    $4DC8,$520B,$5A6E,$62D1         ; $0132CA  entry[4]
; --- 2 descriptor entries with different pattern (DATA) ---
        dc.w    $31CA,$35EB                     ; $0132D2  descriptor entry[5]
        dc.w    $3E2D,$466F                     ; $0132D6  descriptor entry[6]
; --- 8 max-value sentinels (DATA) ---
        dc.w    $7FFF                           ; $0132DA
        dc.w    $7FFF                           ; $0132DC
        dc.w    $7FFF                           ; $0132DE
        dc.w    $7FFF                           ; $0132E0
        dc.w    $7FFF                           ; $0132E2
        dc.w    $7FFF                           ; $0132E4
        dc.w    $7FFF                           ; $0132E6
        dc.w    $7FFF                           ; $0132E8
; --- more descriptor data (DATA) ---
        dc.w    $31CA,$35EB                     ; $0132EA  descriptor entry[7]
        dc.w    $3E2D,$466F                     ; $0132EE  descriptor entry[8]
        dc.w    $14C1                           ; $0132F2
        dc.w    $1D22                           ; $0132F4
        dc.w    $2984                           ; $0132F6
        dc.w    $35E6                           ; $0132F8
        dc.w    $4445                           ; $0132FA
        dc.w    $512B,$6212                     ; $0132FC
        dc.w    $6EF8                           ; $013300
        dc.w    $7FFF                           ; $013302  sentinel
        dc.w    $031F                           ; $013304
        dc.w    $7FFF                           ; $013306  sentinel
        dc.w    $7FFF                           ; $013308  sentinel
        dc.w    $14C1                           ; $01330A
        dc.w    $1D22                           ; $01330C
        dc.w    $2984                           ; $01330E
        dc.w    $35E6                           ; $013310
; --- executable code ---
        jsr     $00882080                       ; $013312  initialization
        move.w  ($FFFFC87E).w,D0                ; $013318  D0 = game_state
        movea.l $013322(PC,D0.W),A1             ; $01331C  A1 = jump_table[state]
        jmp     (A1)                            ; $013320  dispatch
; --- jump table (3 longword entries, DATA -- 68K runtime addresses) ---
        dc.l    $00893346                       ; $013322  [0] -> camera_render_dma_overlay
        dc.l    $008934F0                       ; $013326  [4] -> camera_menu_orch+$28
        dc.l    $00893824                       ; $01332A  [8] -> sh2_scene_reset_cond_handler_by_player_2_flag
; --- post-dispatch code (reached by jump targets) ---
        jsr     object_update(pc)       ; $4EBA $8354
        btst    #6,($FFFFC80E).w                ; $013332  display bit 6 set?
        bne.s   .done                           ; $013338  yes -> done (no advance)
        addq.w  #4,($FFFFC87E).w                ; $01333A  advance game_state
.done:
        jsr     $0088205E                       ; $01333E  SH2 scene transition
        rts                                     ; $013344
