; ============================================================================
; palette_scene_dispatch ($00E90C-$00E926) — Palette Scene Dispatch
; ============================================================================
; CODE ($E90C-$E91A): JSR to init function, MOVE.W from ($C87E) index,
;   MOVEA.L indexed (d0,PC) into A1, JMP (A1)
; DATA ($E91C-$E926): 3 longword handler pointers:
;   Index 0: $0088E93A — sh2_geometry_transfer_and_palette_cycle_handler
;   Index 4: $0088EDDA — sh2_scene_object_update_with_lookup_tables+$11C
;   Index 8: $0088EEF2 — sh2_scene_object_update_with_lookup_tables+$234
; ============================================================================
palette_scene_dispatch:
        jsr     $00882080                       ; $00E90C  sound_command_dispatch_sound_driver_call
        move.w  ($FFFFC87E).w,D0                ; $00E912  D0 = scene handler index
        movea.l .jmp_table(pc,D0.W),A1          ; $00E916  A1 = handler address
        jmp     (A1)                            ; $00E91A  dispatch
.jmp_table:
        dc.l    $0088E93A                       ; $00E91C  handler 0
        dc.l    $0088EDDA                       ; $00E920  handler 1
        dc.l    $0088EEF2                       ; $00E924  handler 2
