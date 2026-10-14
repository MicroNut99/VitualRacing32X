; ============================================================================
; directional_collision_probe — Directional Collision Probe
; ROM Range: $007AD6-$007BAC (214 bytes)
; Probes for collisions in the entity's heading direction. Computes offset
; from heading angle via ROM table at $0093661E, performs tile lookup at
; offset position, checks for track boundary collision via angle_normalize
; and velocity_apply. Probes two points (forward and adjacent) and stores
; surface tracking data in +$C6/+$C8. Falls through to center probe check.
;
; Entry: A0 = entity base pointer, A4 = scratch buffer pointer
; Uses: D0, D1, D2, A0, A1, A2, A3, A4
; Object fields: +$30 x_position, +$34 y_position, +$40 heading,
;   +$46 scale, +$55 collision_flag, +$C6/+$C8 surface_offsets
; Confidence: high
; ============================================================================

; === Forward probe: compute offset from heading angle ===
directional_collision_probe:
        MOVE.W  $0040(A0),D0                    ; $007AD6  ; heading
        ADD.W  $0046(A0),D0                     ; $007ADA  ; + scale
        LEA     $0093661E,A3                    ; $007ADE  ; angle→offset ROM table
        LSR.W  #6,D0                            ; $007AE4  ; angle / 64 = table idx
        ADD.W   D0,D0                           ; $007AE6  ; *2 (2 bytes per entry)
        LEA     $00(A3,D0.W),A3                 ; $007AE8  ; A3 → table entry

; --- Read signed (x,y) offset bytes from table ---
        MOVE.B  (A3)+,D1                        ; $007AEC  ; x offset (signed byte)
        EXT.W   D1                              ; $007AEE
        MOVE.B  (A3),D2                         ; $007AF0  ; y offset (signed byte)
        EXT.W   D2                              ; $007AF2
        ADD.W  $0030(A0),D1                     ; $007AF4  ; D1 = entity_x + offset
        ADD.W  $0034(A0),D2                     ; $007AF8  ; D2 = entity_y + offset

; --- Tile lookup at forward probe position ---
        jsr     track_data_index_calc_table_lookup(pc); $4EBA $F8EA  ; find tile
        MOVE.L  A1,(A4)                         ; $007B00  ; save tile ptr
        jsr     angle_normalize(pc)     ; $4EBA $F988  ; boundary check
        BNE.S  .forward_hit                     ; $007B06
; --- No hit: clear scratch buffer ---
        MOVE.L  #$00000000,(A4)                 ; $007B08
        MOVE.L  #$00000000,$0004(A4)            ; $007B0E
        BRA.S  .probe_adjacent                  ; $007B16

; --- Forward hit: evaluate surface height ---
.forward_hit:
        MOVE.L  A2,$0004(A4)                    ; $007B18  ; save surface ptr
        jsr     plane_eval(pc)          ; $4EBA $FAAA  ; eval height → D1
        BLE.S  .probe_adjacent                  ; $007B20  ; below surface → skip
; --- Smooth height with exponential moving average ---
        MOVE.W  $00C6(A0),D2                    ; $007B22  ; prev forward height
        EXT.L   D2                              ; $007B26
        ADD.L   D2,D1; $007B28  ; accumulate
        ASR.L  #1,D1                            ; $007B2A  ; average
        MOVE.W  D1,$00C6(A0)                    ; $007B2C  ; store smoothed height

; === Adjacent probe: 90-degree offset ($7FF = half table) ===
.probe_adjacent:
        LEA     $07FF(A3),A3                    ; $007B30  ; +2047 entries = ~90 deg
        MOVE.B  (A3)+,D1                        ; $007B34  ; adjacent x offset
        EXT.W   D1                              ; $007B36
        MOVE.B  (A3),D2                         ; $007B38  ; adjacent y offset
        EXT.W   D2                              ; $007B3A
        ADD.W  $0030(A0),D1                     ; $007B3C  ; abs x
        ADD.W  $0034(A0),D2                     ; $007B40  ; abs y

; --- Tile lookup with same-tile optimization ---
        jsr     track_data_index_calc_table_lookup(pc); $4EBA $F8A2
        MOVE.L  (A4),D0                         ; $007B48  ; forward tile ptr
        BEQ.S  .adjacent_new_tile               ; $007B4A  ; no forward → new tile
        CMPA.L  D0,A1                           ; $007B4C  ; same tile?
        BNE.S  .adjacent_new_tile               ; $007B4E  ; no → new tile
; --- Same tile: fast check then full check ---
        MOVEA.L A1,A3                           ; $007B50  ; save tile
        MOVEA.L $0004(A4),A1                    ; $007B52  ; use forward surface
        jsr     angle_normalize+168(pc) ; $4EBA $F9DC  ; fast boundary
        BNE.S  .adjacent_normalized             ; $007B5A  ; hit → done
        MOVEA.L A3,A1                           ; $007B5C  ; restore tile
        jsr     angle_normalize+24(pc)  ; $4EBA $F944  ; full boundary
        BRA.S  .adjacent_normalized             ; $007B62
.adjacent_new_tile:
        jsr     angle_normalize(pc)     ; $4EBA $F926  ; standard check

; --- Evaluate adjacent surface height ---
.adjacent_normalized:
        jsr     plane_eval(pc)          ; $4EBA $FA5E  ; eval height
        BLE.S  .center_probe                    ; $007B6C  ; below → skip
        MOVE.W  $00C8(A0),D2                    ; $007B6E  ; prev adjacent height
        EXT.L   D2                              ; $007B72
        ADD.L   D2,D1; $007B74  ; accumulate
        ASR.L  #1,D1                            ; $007B76  ; average
        MOVE.W  D1,$00C8(A0)                    ; $007B78  ; store smoothed height

; === Center probe: check at entity's own position ===
.center_probe:
        MOVE.W  $0030(A0),D1                    ; $007B7C  ; entity x
        MOVE.W  $0034(A0),D2                    ; $007B80  ; entity y
        MOVE.B  #$01,$0055(A0)                  ; $007B84  ; default = collision
        jsr     track_data_index_calc_table_lookup(pc); $4EBA $F85C  ; find tile
        MOVE.L  (A4),D0                         ; $007B8E  ; forward tile ptr
        DC.W    $672C               ; BEQ.S  $007BBE; $007B90  ; no fwd → falls thru
        CMPA.L  D0,A1                           ; $007B92  ; same tile?
        DC.W    $6628               ; BNE.S  $007BBE; $007B94  ; diff → falls thru
; --- Same tile: try fast then full boundary check ---
        MOVEA.L A1,A3                           ; $007B96
        MOVEA.L $0004(A4),A1                    ; $007B98  ; forward surface
        jsr     angle_normalize+168(pc) ; $4EBA $F996  ; fast check
        DC.W    $6622               ; BNE.S  $007BC4; $007BA0  ; hit → continue
        MOVEA.L A3,A1                           ; $007BA2
        jsr     angle_normalize+24(pc)  ; $4EBA $F8FE  ; full check
        DC.W    $661A               ; BNE.S  $007BC4; $007BA8  ; hit → continue
        RTS                                     ; $007BAA  ; no collision → return
