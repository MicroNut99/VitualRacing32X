; ============================================================================
; track_boundary_collision_detection — Track Boundary Collision Detection
; ROM Range: $00789C-$007A40 (420 bytes)
; Probes 4 points around entity for track boundary collisions. For each
; probe: computes position with offset, calls tile_position_calc to find
; road segment, checks if segment matches current tile (angle_normalize),
; tests collision via velocity_apply, and stores result in entity fields
; +$55 through +$59. Final combined collision flag written to +$55.
;
; Entry: A0 = entity base pointer, A4 = scratch buffer pointer
; Uses: D0, D1, D2, A0, A1, A2, A3, A4
; Object fields: +$30 x_position, +$34 y_position, +$40 heading,
;   +$46 scale, +$55-$59 collision flags per probe,
;   +$CE/+$D2/+$D6/+$DA tile data pointers
; Confidence: high
; ============================================================================

; === Center probe: find current tile from entity position ===
track_boundary_collision_detection:
        MOVE.B  #$00,(-15590).W                 ; $00789C  ; clear surface type
        MOVE.W  $0040(A0),D0                    ; $0078A2  ; heading
        ADD.W  $0046(A0),D0                     ; $0078A6  ; + scale offset
        jsr     track_data_extract_033(pc); $4EBA $FDF6  ; extract track segment
        MOVE.W  $0030(A0),D1                    ; $0078AE  ; D1 = x_pos
        MOVE.W  $0034(A0),D2                    ; $0078B2  ; D2 = y_pos
        jsr     track_data_index_calc_table_lookup(pc); $4EBA $FB30  ; find tile → A1
        MOVE.L  A1,(A4)                         ; $0078BA  ; save center tile ptr
        jsr     angle_normalize(pc)     ; $4EBA $FBCE  ; check boundary
        BNE.S  .center_hit                      ; $0078C0
; --- No collision at center: clear scratch buffer ---
        MOVE.L  #$00000000,(A4)                 ; $0078C2  ; clear tile ptr
        MOVE.L  #$00000000,$0004(A4)            ; $0078C8  ; clear surface ptr
        BRA.S  .probe_1                         ; $0078D0
; --- Center hit: store surface data for tracking ---
.center_hit:
        MOVE.L  A2,$0004(A4)                    ; $0078D2  ; surface data ptr
        MOVE.L  A2,$00CE(A0)                    ; $0078D6  ; entity tile data[0]
        MOVE.B  $0018(A2),D0                    ; $0078DA  ; surface type byte
        MOVE.B  D0,(-15591).W                   ; $0078DE  ; store global surface
        MOVE.W  D1,(-16176).W                   ; $0078E2  ; store probe x
        MOVE.W  D2,(-16174).W                   ; $0078E6  ; store probe y

; === Probe 1: front-left offset ===
.probe_1:
        MOVE.W  $0030(A0),D1                    ; $0078EA  ; x_pos
        ADD.W  (-16338).W,D1                    ; $0078EE  ; + probe 1 x offset
        MOVE.W  $0034(A0),D2                    ; $0078F2  ; y_pos
        ADD.W  (-16334).W,D2                    ; $0078F6  ; + probe 1 y offset
        MOVE.B  #$01,$0056(A0)                  ; $0078FA  ; default = collision
        jsr     track_data_index_calc_table_lookup(pc); $4EBA $FAE6  ; find tile
; --- Check if same tile as center (optimization) ---
        MOVE.L  (A4),D0                         ; $007904  ; center tile ptr
        BEQ.S  .probe_1_new_tile                ; $007906  ; no center → new tile
        CMPA.L  D0,A1                           ; $007908  ; same tile?
        BNE.S  .probe_1_new_tile                ; $00790A  ; different → new tile
; --- Same tile: try fast boundary check first ---
        MOVEA.L A1,A3                           ; $00790C  ; save tile ptr
        MOVEA.L $0004(A4),A1                    ; $00790E  ; use center surface
        jsr     angle_normalize+168(pc) ; $4EBA $FC20  ; fast boundary check
        BNE.S  .probe_1_collision               ; $007916  ; hit → collision
        MOVEA.L A3,A1                           ; $007918  ; restore tile ptr
        jsr     angle_normalize+24(pc)  ; $4EBA $FB88  ; full boundary check
        BRA.S  .probe_1_check_result            ; $00791E
.probe_1_new_tile:
        jsr     angle_normalize(pc)     ; $4EBA $FB6A  ; standard check
.probe_1_check_result:
        BEQ.S  .probe_2                         ; $007924  ; no collision → next
.probe_1_collision:
        MOVE.L  A2,$00D2(A0)                    ; $007926  ; tile data[1]
        MOVE.W  D1,(-16172).W                   ; $00792A  ; store collision x
        MOVE.W  D2,(-16170).W                   ; $00792E  ; store collision y
        jsr     object_type_dispatch(pc); $4EBA $010C  ; classify surface
        MOVE.B  D0,$0056(A0)                    ; $007936  ; store probe 1 flag

; === Probe 2: front-right offset ===
.probe_2:
        MOVE.W  $0030(A0),D1                    ; $00793A  ; x_pos
        ADD.W  (-16332).W,D1                    ; $00793E  ; + probe 2 x offset
        MOVE.W  $0034(A0),D2                    ; $007942  ; y_pos
        ADD.W  (-16328).W,D2                    ; $007946  ; + probe 2 y offset
        MOVE.B  #$01,$0057(A0)                  ; $00794A  ; default = collision
        jsr     track_data_index_calc_table_lookup(pc); $4EBA $FA96
        MOVE.L  (A4),D0                         ; $007954  ; center tile ptr
        BEQ.S  .probe_2_new_tile                ; $007956
        CMPA.L  D0,A1                           ; $007958  ; same tile?
        BNE.S  .probe_2_new_tile                ; $00795A
        MOVEA.L A1,A3                           ; $00795C
        MOVEA.L $0004(A4),A1                    ; $00795E  ; center surface
        jsr     angle_normalize+168(pc) ; $4EBA $FBD0  ; fast check
        BNE.S  .probe_2_collision               ; $007966
        MOVEA.L A3,A1                           ; $007968
        jsr     angle_normalize+24(pc)  ; $4EBA $FB38  ; full check
        BRA.S  .probe_2_check_result            ; $00796E
.probe_2_new_tile:
        jsr     angle_normalize(pc)     ; $4EBA $FB1A
.probe_2_check_result:
        BEQ.S  .probe_3                         ; $007974
.probe_2_collision:
        MOVE.L  A2,$00D6(A0)                    ; $007976  ; tile data[2]
        MOVE.W  D1,(-16168).W                   ; $00797A  ; collision x
        MOVE.W  D2,(-16166).W                   ; $00797E  ; collision y
        jsr     object_type_dispatch(pc); $4EBA $00BC  ; classify surface
        MOVE.B  D0,$0057(A0)                    ; $007986  ; store probe 2 flag

; === Probe 3: rear-left offset ===
.probe_3:
        MOVE.W  $0030(A0),D1                    ; $00798A  ; x_pos
        ADD.W  (-16326).W,D1                    ; $00798E  ; + probe 3 x offset
        MOVE.W  $0034(A0),D2                    ; $007992  ; y_pos
        ADD.W  (-16322).W,D2                    ; $007996  ; + probe 3 y offset
        MOVE.B  #$01,$0058(A0)                  ; $00799A  ; default = collision
        jsr     track_data_index_calc_table_lookup(pc); $4EBA $FA46
        MOVE.L  (A4),D0                         ; $0079A4  ; center tile ptr
        BEQ.S  .probe_3_new_tile                ; $0079A6
        CMPA.L  D0,A1                           ; $0079A8  ; same tile?
        BNE.S  .probe_3_new_tile                ; $0079AA
        MOVEA.L A1,A3                           ; $0079AC
        MOVEA.L $0004(A4),A1                    ; $0079AE  ; center surface
        jsr     angle_normalize+168(pc) ; $4EBA $FB80  ; fast check
        BNE.S  .probe_3_collision               ; $0079B6
        MOVEA.L A3,A1                           ; $0079B8
        jsr     angle_normalize+24(pc)  ; $4EBA $FAE8  ; full check
        BRA.S  .probe_3_check_result            ; $0079BE
.probe_3_new_tile:
        jsr     angle_normalize(pc)     ; $4EBA $FACA
.probe_3_check_result:
        BEQ.S  .probe_4                         ; $0079C4
.probe_3_collision:
        MOVE.L  A2,$00DA(A0)                    ; $0079C6  ; tile data[3]
        MOVE.W  D1,(-16164).W                   ; $0079CA  ; collision x
        MOVE.W  D2,(-16162).W                   ; $0079CE  ; collision y
        jsr     object_type_dispatch(pc); $4EBA $006C  ; classify surface
        MOVE.B  D0,$0058(A0)                    ; $0079D6  ; store probe 3 flag

; === Probe 4: rear-right offset ===
.probe_4:
        MOVE.W  $0030(A0),D1                    ; $0079DA  ; x_pos
        ADD.W  (-16320).W,D1                    ; $0079DE  ; + probe 4 x offset
        MOVE.W  $0034(A0),D2                    ; $0079E2  ; y_pos
        ADD.W  (-16316).W,D2                    ; $0079E6  ; + probe 4 y offset
        MOVE.B  #$01,$0059(A0)                  ; $0079EA  ; default = collision
        jsr     track_data_index_calc_table_lookup(pc); $4EBA $F9F6
        MOVE.L  (A4),D0                         ; $0079F4  ; center tile ptr
        BEQ.S  .probe_4_new_tile                ; $0079F6
        CMPA.L  D0,A1                           ; $0079F8  ; same tile?
        BNE.S  .probe_4_new_tile                ; $0079FA
        MOVEA.L A1,A3                           ; $0079FC
        MOVEA.L $0004(A4),A1                    ; $0079FE  ; center surface
        jsr     angle_normalize+168(pc) ; $4EBA $FB30  ; fast check
        BNE.S  .probe_4_collision               ; $007A06
        MOVEA.L A3,A1                           ; $007A08
        jsr     angle_normalize+24(pc)  ; $4EBA $FA98  ; full check
        BRA.S  .probe_4_check_result            ; $007A0E
.probe_4_new_tile:
        jsr     angle_normalize(pc)     ; $4EBA $FA7A
.probe_4_check_result:
        BEQ.S  .combine_flags                   ; $007A14
.probe_4_collision:
        MOVE.L  A2,$00DE(A0)                    ; $007A16  ; tile data[4]
        MOVE.W  D1,(-16160).W                   ; $007A1A  ; collision x
        MOVE.W  D2,(-16158).W                   ; $007A1E  ; collision y
        jsr     object_type_dispatch(pc); $4EBA $001C  ; classify surface
        MOVE.B  D0,$0059(A0)                    ; $007A26  ; store probe 4 flag

; === Combine all 4 probe flags into master collision byte ===
.combine_flags:
        MOVE.B  $0056(A0),D0                    ; $007A2A  ; probe 1
        OR.B   $0057(A0),D0                     ; $007A2E  ; | probe 2
        OR.B   $0058(A0),D0                     ; $007A32  ; | probe 3
        OR.B   $0059(A0),D0                     ; $007A36  ; | probe 4
        MOVE.B  D0,$0055(A0)                    ; $007A3A  ; combined flag
        RTS                                     ; $007A3E
