; ============================================================================
; collision_response_surface_tracking — Collision Response + Surface Tracking
; ROM Range: $007700-$00789C (412 bytes)
; Iterative collision response with surface tracking. Calls obj_frame_calc
; ($00789C), then iteratively adjusts heading (+$40), scale (+$46), X (+$30),
; and Y (+$34) in 1/4 steps up to 4 iterations, checking collision flag
; (+$55 bit 0) each time. On collision, reverses last step. Second half
; performs surface-relative calculations on 4 neighboring probe points
; using tile lookup data from entity fields +$CE/+$D2/+$D6/+$DA.
;
; Entry: A0 = entity base pointer
; Uses: D0, D1, D2, D3, D4, D5, D6, D7
; Object fields: +$30 x_pos, +$32 y_sub, +$34 y_pos, +$36/+$38 prev_pos,
;   +$40 heading, +$42 prev_heading, +$46 scale, +$48 prev_scale,
;   +$55 collision_flag, +$5A/+$5C/+$5E/+$32 surface_offsets
; Confidence: high
; ============================================================================

; === Initial collision detection ===
collision_response_surface_tracking:
        jsr     track_boundary_collision_detection(pc); $4EBA $019A  ; 4-point probe
        CMPI.W  #$0000,$0062(A0)                ; $007704  ; collision state > 0?
        BGT.W  .save_current_pos                ; $00770A  ; active collision → skip
        BTST    #0,$0055(A0)                    ; $00770E  ; any probe hit?
        BEQ.W  .save_current_pos                ; $007714  ; no collision → skip

; === Binary search: compute 1/4 step deltas for iteration ===
        MOVE.W  $0040(A0),D3                    ; $007718  ; current heading
        SUB.W  $0042(A0),D3                     ; $00771C  ; - prev heading
        ASR.W  #2,D3                            ; $007720  ; D3 = heading delta/4
        MOVE.W  $0046(A0),D4                    ; $007722  ; current scale
        SUB.W  $0048(A0),D4                     ; $007726  ; - prev scale
        ASR.W  #2,D4                            ; $00772A  ; D4 = scale delta/4
        MOVE.W  $0030(A0),D5                    ; $00772C  ; current x
        SUB.W  $0036(A0),D5                     ; $007730  ; - prev x
        ASR.W  #2,D5                            ; $007734  ; D5 = x delta/4
        MOVE.W  $0034(A0),D6                    ; $007736  ; current y
        SUB.W  $0038(A0),D6                     ; $00773A  ; - prev y
        ASR.W  #2,D6                            ; $00773E  ; D6 = y delta/4

; --- Reset to previous frame position ---
        MOVE.W  $0036(A0),$0030(A0)             ; $007740  ; x = prev_x
        MOVE.W  $0038(A0),$0034(A0)             ; $007746  ; y = prev_y
        MOVE.W  $0042(A0),$0040(A0)             ; $00774C  ; heading = prev_heading
        MOVE.W  $0048(A0),$0046(A0)             ; $007752  ; scale = prev_scale

; === Iteration 1: advance by 1/4 step ===
        ADD.W  D3,$0040(A0)                     ; $007758  ; heading += delta/4
        ADD.W  D4,$0046(A0)                     ; $00775C  ; scale += delta/4
        ADD.W  D5,$0030(A0)                     ; $007760  ; x += delta/4
        ADD.W  D6,$0034(A0)                     ; $007764  ; y += delta/4
        MOVEM.L D0/D1/D2/D3/D4/D5/D6/D7,-(A7)   ; $007768  ; save regs
        jsr     track_boundary_collision_detection(pc); $4EBA $012E  ; test
        MOVEM.L (A7)+,D0/D1/D2/D3/D4/D5/D6/D7   ; $007770
        BTST    #0,$0055(A0)                    ; $007774  ; collision?
        BNE.W  .revert_step                     ; $00777A  ; yes → undo

; === Iteration 2: advance to 2/4 ===
        ADD.W  D3,$0040(A0)                     ; $00777E
        ADD.W  D4,$0046(A0)                     ; $007782
        ADD.W  D5,$0030(A0)                     ; $007786
        ADD.W  D6,$0034(A0)                     ; $00778A
        MOVEM.L D0/D1/D2/D3/D4/D5/D6/D7,-(A7)   ; $00778E
        jsr     track_boundary_collision_detection(pc); $4EBA $0108
        MOVEM.L (A7)+,D0/D1/D2/D3/D4/D5/D6/D7   ; $007796
        BTST    #0,$0055(A0)                    ; $00779A
        BNE.S  .revert_step                     ; $0077A0

; === Iteration 3: advance to 3/4 ===
        ADD.W  D3,$0040(A0)                     ; $0077A2
        ADD.W  D4,$0046(A0)                     ; $0077A6
        ADD.W  D5,$0030(A0)                     ; $0077AA
        ADD.W  D6,$0034(A0)                     ; $0077AE
        MOVEM.L D0/D1/D2/D3/D4/D5/D6/D7,-(A7)   ; $0077B2
        jsr     track_boundary_collision_detection(pc); $4EBA $00E4
        MOVEM.L (A7)+,D0/D1/D2/D3/D4/D5/D6/D7   ; $0077BA
        BTST    #0,$0055(A0)                    ; $0077BE
        BNE.S  .revert_step                     ; $0077C4

; === Iteration 4: advance to 4/4 (full step) ===
        ADD.W  D3,$0040(A0)                     ; $0077C6
        ADD.W  D4,$0046(A0)                     ; $0077CA
        ADD.W  D5,$0030(A0)                     ; $0077CE
        ADD.W  D6,$0034(A0)                     ; $0077D2
        MOVEM.L D0/D1/D2/D3/D4/D5/D6/D7,-(A7)   ; $0077D6
        jsr     track_boundary_collision_detection(pc); $4EBA $00C0
        MOVEM.L (A7)+,D0/D1/D2/D3/D4/D5/D6/D7   ; $0077DE
        BTST    #0,$0055(A0)                    ; $0077E2
        BEQ.S  .save_current_pos                ; $0077E8  ; no collision → keep

; --- Collision: revert last 1/4 step ---
.revert_step:
        SUB.W  D3,$0040(A0)                     ; $0077EA  ; undo heading
        SUB.W  D4,$0046(A0)                     ; $0077EE  ; undo scale
        SUB.W  D5,$0030(A0)                     ; $0077F2  ; undo x
        SUB.W  D6,$0034(A0)                     ; $0077F6  ; undo y

; --- Snapshot current as previous for next frame ---
.save_current_pos:
        MOVE.W  $0040(A0),$0042(A0)             ; $0077FA  ; prev_heading = heading
        MOVE.W  $0046(A0),$0048(A0)             ; $007800  ; prev_scale = scale
        MOVE.W  $0030(A0),$0036(A0)             ; $007806  ; prev_x = x
        MOVE.W  $0034(A0),$0038(A0)             ; $00780C  ; prev_y = y
        BRA.W  .surface_tracking                ; $007812
        jsr     track_boundary_collision_detection(pc); $4EBA $0084  ; dead code

; === Surface tracking: evaluate height at 4 probe points ===
; Each probe: plane_eval returns height, then exponential
; moving average: new = (old + height) / 2
.surface_tracking:
        MOVEA.L $00D2(A0),A2                    ; $00781A  ; probe 1 tile data
        MOVE.W  (-16172).W,D1                   ; $00781E  ; probe 1 x
        MOVE.W  (-16170).W,D2                   ; $007822  ; probe 1 y
        jsr     plane_eval+24(pc)       ; $4EBA $FDB8  ; eval surface height
        BLE.S  .skip_probe_a                    ; $00782A  ; below surface → skip
        MOVE.W  $005A(A0),D2                    ; $00782C  ; prev height offset
        EXT.L   D2                              ; $007830
        ADD.L   D2,D1; $007832  ; accumulate
        ASR.L  #1,D1                            ; $007834  ; average
        MOVE.W  D1,$005A(A0)                    ; $007836  ; store smoothed height
.skip_probe_a:
        MOVEA.L $00D6(A0),A2                    ; $00783A  ; probe 2 tile data
        MOVE.W  (-16168).W,D1                   ; $00783E  ; probe 2 x
        MOVE.W  (-16166).W,D2                   ; $007842  ; probe 2 y
        jsr     plane_eval+24(pc)       ; $4EBA $FD98
        BLE.S  .skip_probe_b                    ; $00784A
        MOVE.W  $005C(A0),D2                    ; $00784C  ; prev height offset
        EXT.L   D2                              ; $007850
        ADD.L   D2,D1; $007852
        ASR.L  #1,D1                            ; $007854
        MOVE.W  D1,$005C(A0)                    ; $007856
.skip_probe_b:
        MOVEA.L $00DA(A0),A2                    ; $00785A  ; probe 3 tile data
        MOVE.W  (-16164).W,D1                   ; $00785E  ; probe 3 x
        MOVE.W  (-16162).W,D2                   ; $007862  ; probe 3 y
        jsr     plane_eval+24(pc)       ; $4EBA $FD78
        BLE.S  .skip_probe_c                    ; $00786A
        MOVE.W  $005E(A0),D2                    ; $00786C  ; prev height offset
        EXT.L   D2                              ; $007870
        ADD.L   D2,D1; $007872
        ASR.L  #1,D1                            ; $007874
        MOVE.W  D1,$005E(A0)                    ; $007876
.skip_probe_c:
        MOVEA.L $00CE(A0),A2                    ; $00787A  ; center tile data
        MOVE.W  (-16176).W,D1                   ; $00787E  ; center x
        MOVE.W  (-16174).W,D2                   ; $007882  ; center y
        jsr     plane_eval+24(pc)       ; $4EBA $FD58
        BLE.S  .skip_probe_d                    ; $00788A
        MOVE.W  $0032(A0),D2                    ; $00788C  ; prev y_sub
        EXT.L   D2                              ; $007890
        ADD.L   D2,D1; $007892
        ASR.L  #1,D1                            ; $007894
        MOVE.W  D1,$0032(A0)                    ; $007896  ; smoothed y_sub
.skip_probe_d:
        RTS                                     ; $00789A
