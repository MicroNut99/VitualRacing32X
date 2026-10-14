; ============================================================================
; drift_physics_and_camera_offset_calc — Drift Physics and Camera Offset Calculation
; ROM Range: $009688-$009802 (378 bytes)
; Computes lateral drift from steering velocity +$8E, applies speed-based
; scaling with sine lookup, updates heading mirror +$3C. Calculates camera
; follow distance from entity displacement fields +$5A/+$5C, speed +$06,
; and applies polynomial scaling. Manages drift accumulator +$AA with
; decay and heading snap-back toward target +$40.
;
; Entry: A0 = entity pointer
; Uses: D0, D1, D2, D3, A0
; Calls: $008F52 (sine_lookup)
; Object fields: +$04 speed, +$06 display speed, +$0C slope, +$1E target
;   heading, +$3C heading mirror, +$40 heading angle, +$5A trail X,
;   +$5C trail Y, +$76 camera dist, +$8E steer vel, +$90 drift rate,
;   +$92 slide, +$AA drift accum
; Confidence: high
; ============================================================================

; --- Phase 1: Compute drift rate from steering velocity ---
drift_physics_and_camera_offset_calc:
        MOVE.W  $008E(A0),D0                    ; $009688 ; steer_vel
        ASR.W  #4,D0                            ; $00968C ; steer_vel / 16
        MOVE.W  #$0497,D1                       ; $00968E ; max speed constant
        SUB.W  $0006(A0),D1                     ; $009692 ; remaining = max - cur_speed
        MULS    D0,D1                           ; $009696 ; steer * remaining
        DIVS    #$0497,D1                       ; $009698 ; normalize to [0..1]
        ADD.W   D1,D0                           ; $00969C ; drift = steer + speed-scaled steer
        MOVE.W  D0,$0090(A0)                    ; $00969E ; store drift_rate
; --- Low-speed sine correction (below speed $80) ---
        CMPI.W  #$0080,$0004(A0)                ; $0096A2 ; speed >= 128?
        BGE.S  .apply_speed_scale               ; $0096A8 ; skip sine blend
        MOVE.W  D0,D2                           ; $0096AA ; save drift
        MOVE.W  $0004(A0),D0                    ; $0096AC ; load speed
        LSL.W  #7,D0                            ; $0096B0 ; scale to angle range
        ADDI.W  #$8000,D0                       ; $0096B2 ; offset into sine table
        jsr     sine_cosine_quadrant_lookup+4(pc); $4EBA $F89A ; cosine lookup
        ADDI.W  #$0100,D0                       ; $0096BA ; bias cosine result
        MULS    $0090(A0),D0                    ; $0096BE ; cosine * drift_rate
        ASR.L  #6,D0                            ; $0096C2 ; /64
        ADD.W   D2,D0                           ; $0096C4 ; add original drift
; --- Scale drift by speed ---
.apply_speed_scale:
        MULS    $0004(A0),D0                    ; $0096C6 ; drift * speed
        MOVEQ   #$0A,D2                         ; $0096CA ; shift count = 10
        ASR.L  D2,D0                            ; $0096CC ; /1024
; --- Slope adjustment: amplify on downhill ---
        MOVE.W  $0076(A0),D2                    ; $0096CE ; cam_dist
        MOVE.W  $000C(A0),D3                    ; $0096D2 ; slope
        BPL.S  .after_slope_adjust              ; $0096D6 ; skip if uphill
        ADD.W   D3,D3                           ; $0096D8 ; slope * 2
        SUB.W   D3,D2                           ; $0096DA ; cam_dist -= 2*slope
.after_slope_adjust:
        MULS    D2,D0                           ; $0096DC ; drift * adjusted_dist
        ASR.L  #8,D0                            ; $0096DE ; /256
; --- Slide damping ---
        TST.W  $0092(A0)                        ; $0096E0 ; slide active?
        BLE.S  .after_slide_scale               ; $0096E4
        MOVE.W  #$0028,D1                       ; $0096E6 ; max slide = 40
        SUB.W  $0092(A0),D1                     ; $0096EA ; remaining slide margin
        MULS    D1,D0                           ; $0096EE ; scale by margin
        ASR.L  #5,D0                            ; $0096F0 ; /32
; --- Accumulate heading offset (1.5x or 2x based on flag) ---
.after_slide_scale:
        MOVE.W  D0,D2                           ; $0096F2 ; save drift
        MOVE.W  D0,D1                           ; $0096F4
        ASR.W  #1,D1                            ; $0096F6 ; drift/2
        ADD.W   D1,D0                           ; $0096F8 ; D0 = drift * 1.5
        TST.B  (-15589).W                       ; $0096FA ; extra drift flag
        BEQ.S  .update_heading                  ; $0096FE
        ASR.W  #1,D2                            ; $009700 ; +drift/2 more
        ADD.W   D2,D0                           ; $009702 ; D0 = drift * 2.0
.update_heading:
        ADD.W  D0,$003C(A0)                     ; $009704 ; heading_mirror += drift
; --- Heading snap-back toward target when within threshold ---
        MOVE.W  $003C(A0),D0                    ; $009708 ; heading_mirror
        SUB.W  $001E(A0),D0                     ; $00970C ; - target_heading
        BPL.S  .heading_abs_diff                ; $009710
        NEG.W  D0                               ; $009712
.heading_abs_diff:
        CMPI.W  #$0222,D0                       ; $009714 ; threshold = $222
        BGE.S  .reset_snap_counter              ; $009718 ; too far, reset
        ADDQ.W  #1,(-16382).W                   ; $00971A ; snap frame counter++
        CMPI.W  #$0004,(-16382).W               ; $00971E ; need 4 consecutive frames
        BLT.S  .calc_trail_delta                ; $009724
; snap-back: nudge heading toward target, clamped to +/-$12
        MOVE.W  $001E(A0),D0                    ; $009726 ; target_heading
        SUB.W  $0040(A0),D0                     ; $00972A ; - heading_angle
        CMPI.W  #$0012,D0                       ; $00972E ; clamp +18
        BLE.S  .clamp_snap_high                 ; $009732
        MOVE.W  #$0012,D0                       ; $009734
.clamp_snap_high:
        CMPI.W  #$FFEE,D0                       ; $009738 ; clamp -18
        BGE.S  .apply_snap                      ; $00973C
        MOVE.W  #$FFEE,D0                       ; $00973E
.apply_snap:
        ADD.W  D0,$003C(A0)                     ; $009742 ; apply snap correction
        BRA.S  .calc_trail_delta                ; $009746
.reset_snap_counter:
        CLR.W  (-16382).W                       ; $009748 ; reset snap counter
; --- Phase 2: Camera follow distance from trail displacement ---
.calc_trail_delta:
        MOVE.W  $005C(A0),D0                    ; $00974C ; trail_Y
        SUB.W  $005A(A0),D0                     ; $009750 ; - trail_X = displacement
        MOVE.W  $0090(A0),D1                    ; $009754 ; drift_rate
        BPL.S  .trail_signs_ok                  ; $009758 ; match signs
        NEG.W  D0                               ; $00975A
        NEG.W  D1                               ; $00975C
.trail_signs_ok:
        CMPI.W  #$0190,D0                       ; $00975E ; clamp to +400
        BLE.S  .clamp_trail_high                ; $009762
        MOVE.W  #$0190,D0                       ; $009764
.clamp_trail_high:
        CMPI.W  #$FFCE,D0                       ; $009768 ; clamp to -50
        BGE.S  .clamp_trail_low_done            ; $00976C
        MOVE.W  #$FFCE,D0                       ; $00976E
; --- Polynomial distance: base + trail*5/16 - speed^2 * drift ---
.clamp_trail_low_done:
        LSL.W  #4,D0                            ; $009772 ; trail << 4
        MOVE.W  D0,D2                           ; $009774 ; save
        ADD.W   D0,D0                           ; $009776 ; *2
        ADD.W   D0,D0                           ; $009778 ; *4
        ADD.W   D2,D0                           ; $00977A ; *5 total
        ASR.W  #8,D0                            ; $00977C ; /256 → trail*5/16
        MOVE.W  $0006(A0),D2                    ; $00977E ; display_speed
        ADD.W   D2,D2                           ; $009782 ; *2
        ADD.W   D2,D2                           ; $009784 ; *4
        MOVE.W  D2,D3                           ; $009786 ; save *4
        ADD.W   D3,D3                           ; $009788 ; *8
        ADD.W   D3,D3                           ; $00978A ; *16
        ADD.W   D3,D2                           ; $00978C ; D2 = speed*20
        MULS    D2,D2                           ; $00978E ; (speed*20)^2
        SWAP    D2                              ; $009790 ; >>16
        MULS    D1,D2                           ; $009792 ; * drift_rate
        MOVEQ   #$0D,D1                         ; $009794 ; shift = 13
        ASR.L  D1,D2                            ; $009796 ; >>13
        ASR.W  #3,D2                            ; $009798 ; >>3 (total >>16)
        MOVE.W  D2,D1                           ; $00979A
        ASR.W  #1,D1                            ; $00979C ; D2 * 1.5
        ADD.W   D1,D2                           ; $00979E
        ADDI.W  #$0188,D0                       ; $0097A0 ; base distance = $188
        SUB.W   D2,D0                           ; $0097A4 ; subtract speed^2 term
; --- Slope offset on camera distance ---
        MOVE.W  $000C(A0),D1                    ; $0097A6 ; slope
        NEG.W  D1                               ; $0097AA ; invert for camera
        LSL.W  #4,D1                            ; $0097AC ; *16
        CMPI.W  #$0040,D1                       ; $0097AE ; clamp +64
        BLE.S  .clamp_slope_high                ; $0097B2
        MOVE.W  #$0040,D1                       ; $0097B4
.clamp_slope_high:
        CMPI.W  #$FFF0,D1                       ; $0097B8 ; clamp -16
        BGE.S  .clamp_slope_low_done            ; $0097BC
        MOVE.W  #$FFF0,D1                       ; $0097BE
.clamp_slope_low_done:
        ADD.W   D1,D0                           ; $0097C2 ; apply slope offset
; --- Final distance clamping ---
        CMPI.W  #$0040,D0                       ; $0097C4 ; min dist = 64
        BGE.S  .clamp_dist_min                  ; $0097C8
        MOVEQ   #$40,D0                         ; $0097CA
.clamp_dist_min:
        CMP.W  (-16152).W,D0                    ; $0097CC ; max dist from RAM
        BLE.S  .clamp_dist_max                  ; $0097D0
        MOVE.W  (-16152).W,D0                   ; $0097D2
; --- Drift accumulator decay and smooth distance update ---
.clamp_dist_max:
        TST.W  $00AA(A0)                        ; $0097D6 ; drift_accum > 0?
        BLE.S  .check_drift_accum               ; $0097DA
        SUBQ.W  #8,$00AA(A0)                    ; $0097DC ; decay by 8/frame
.check_drift_accum:
        CMPI.W  #$0050,$00AA(A0)                ; $0097E0 ; accum > $50?
        BGT.S  .set_cam_dist                    ; $0097E6 ; snap directly
        MOVE.W  $0076(A0),D1                    ; $0097E8 ; current cam_dist
        SUB.W   D0,D1                           ; $0097EC ; delta = cur - target
        CMPI.W  #$000C,D1                       ; $0097EE ; delta > 12?
        BLE.S  .set_cam_dist                    ; $0097F2 ; close enough, snap
        SUBI.W  #$000C,$0076(A0)                ; $0097F4 ; ease in by 12/frame
        BRA.S  .done                            ; $0097FA
.set_cam_dist:
        MOVE.W  D0,$0076(A0)                    ; $0097FC ; store cam_dist
.done:
        RTS                                     ; $009800
