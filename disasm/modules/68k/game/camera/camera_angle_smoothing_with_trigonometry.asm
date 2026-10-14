; ============================================================================
; camera_angle_smoothing_with_trigonometry — Camera Angle Smoothing with Trigonometry
; ROM Range: $008DC0-$008EB6 (246 bytes)
; Computes smoothed camera angles using ai_steering_calc for initial angle,
; then applies cosine/sine lookups with conditional blending. Smooths both
; horizontal and vertical camera rotation with damping. Dual-axis processing
; with mirrored logic for each axis.
;
; Entry: A0 = entity pointer
; Uses: D0, D1, D2, D3, A0
; Calls: $008F4E (cosine_lookup), $008F52 (sine_lookup),
;        $00A7A0 (ai_steering_calc), $00A7A4 (steering variant)
; Object fields: +$30 x_pos, +$32 z_pos, +$34 y_pos
; Confidence: high
; ============================================================================

; --- Compute raw horizontal angle from entity-to-waypoint ---
camera_angle_smoothing_with_trigonometry:
        MOVE.W  (-16198).W,D0                   ; $008DC0 ; waypoint X
        MOVE.W  (-16194).W,D1                   ; $008DC4 ; waypoint Y
        MOVE.W  $0030(A0),D2                    ; $008DC8 ; entity x_pos
        MOVE.W  $0034(A0),D3                    ; $008DCC ; entity y_pos
        jsr     ai_steering_calc(pc)    ; $4EBA $19CE ; → D0 = angle
        SUBI.W  #$4000,D0                       ; $008DD4 ; rotate -90 degrees
        NEG.W  D0                               ; $008DD8 ; flip direction
; --- Smooth horizontal angle with previous frame ---
        TST.W  (-16126).W                       ; $008DDA ; prev H angle exists?
        BEQ.S  .store_h_angle                   ; $008DDE ; first frame, no blend
        MOVEQ   #$00,D3                         ; $008DE0
        TST.W  D0                               ; $008DE2 ; new angle sign
        BMI.S  .h_angle_negative                ; $008DE4
; new >= 0: check prev sign for quadrant wrap
        MOVE.W  (-16126).W,D3                   ; $008DE6 ; prev H angle
        BPL.S  .h_blend_long                    ; $008DEA ; same sign, safe
.h_check_quadrant:
; opposite signs: check if wrapping through $8000
        CMPI.W  #$C000,D0                       ; $008DEC ; in range $C000-$FFFF?
        BCC.S  .h_blend_word                    ; $008DF0 ; near zero, word blend
        CMPI.W  #$4000,D0                       ; $008DF2 ; in range $0000-$3FFF?
        BCC.S  .h_blend_long                    ; $008DF6 ; mid-range, long blend
.h_blend_word:
        ADD.W   D3,D0                           ; $008DF8 ; avg = (new+prev)/2
        ASR.W  #1,D0                            ; $008DFA
        BRA.S  .store_h_angle                   ; $008DFC
.h_angle_negative:
        MOVE.W  (-16126).W,D3                   ; $008DFE ; prev H angle
        BPL.S  .h_check_quadrant                ; $008E02 ; opposite signs
.h_blend_long:
; same sign or needs unsigned blend to avoid wrap
        ANDI.L  #$0000FFFF,D0                   ; $008E04 ; zero-extend
        ADD.L   D3,D0                           ; $008E0A ; unsigned sum
        ASR.L  #1,D0                            ; $008E0C ; /2 = smooth avg
.store_h_angle:
        MOVE.W  D0,(-16190).W                   ; $008E0E ; output H angle
        MOVE.W  D0,(-16126).W                   ; $008E12 ; save for next frame
; --- Select sin/cos based on angle quadrant ---
; Near 0 or $FFFF (facing forward/back): use sine
; Near $8000 (facing sideways): use cosine
        CMPI.W  #$1000,D0                       ; $008E16 ; angle < $1000?
        BCS.S  .sine_path                       ; $008E1A ; near 0, use sine
        CMPI.W  #$F000,D0                       ; $008E1C ; angle >= $F000?
        BCC.S  .sine_path                       ; $008E20 ; near $FFFF, sine
        CMPI.W  #$9000,D0                       ; $008E22 ; angle >= $9000?
        BCC.S  .cosine_path                     ; $008E26 ; near $8000, cosine
        CMPI.W  #$7000,D0                       ; $008E28 ; angle < $7000?
        BCS.S  .cosine_path                     ; $008E2C ; mid-range, cosine
; --- Sine path: entity X delta, fallback to Y ---
.sine_path:
        jsr     sine_cosine_quadrant_lookup(pc); $4EBA $011E ; sin(angle)
        MOVE.W  $0030(A0),D2                    ; $008E32 ; entity X
        SUB.W  (-16198).W,D2                    ; $008E36 ; - waypoint X = dX
        TST.W  D0                               ; $008E3A ; sin result zero?
        BEQ.S  .calc_vertical                   ; $008E3C ; skip divide
        MOVE.W  $0034(A0),D2                    ; $008E3E ; entity Y
        SUB.W  (-16194).W,D2                    ; $008E42 ; - waypoint Y = dY
        BRA.S  .compute_ratio                   ; $008E46
; --- Cosine path: entity Y delta, fallback to X ---
.cosine_path:
        jsr     sine_cosine_quadrant_lookup+4(pc); $4EBA $0108 ; cos(angle)
        MOVE.W  $0034(A0),D2                    ; $008E4C ; entity Y
        SUB.W  (-16194).W,D2                    ; $008E50 ; - waypoint Y = dY
        TST.W  D0                               ; $008E54 ; cos result zero?
        BEQ.S  .calc_vertical                   ; $008E56 ; skip divide
        MOVE.W  $0030(A0),D2                    ; $008E58 ; entity X
        SUB.W  (-16198).W,D2                    ; $008E5C ; - waypoint X = dX
; --- Compute distance ratio: (delta << 8) / trig ---
.compute_ratio:
        EXT.L   D2                              ; $008E60 ; sign-extend delta
        ASL.L  #8,D2                            ; $008E62 ; 8.8 fixed point
        DIVS    D0,D2                           ; $008E64 ; ratio = delta/trig
; --- Vertical angle: height delta smoothed ---
.calc_vertical:
        MOVE.W  $0032(A0),D3                    ; $008E66 ; entity z_pos (height)
        SUB.W  (-16196).W,D3                    ; $008E6A ; - waypoint Z = dZ
        ASR.W  #4,D3                            ; $008E6E ; dZ / 16
        MOVE.W  D2,D2                           ; $008E70 ; (NOP, optimizer artifact)
        jsr     ai_steering_calc+4(pc)  ; $4EBA $1930 ; → D0 = V angle
        NEG.W  D0                               ; $008E76 ; flip V angle
; --- Smooth vertical angle (same logic as horizontal) ---
        TST.W  (-16128).W                       ; $008E78 ; prev V angle exists?
        BEQ.S  .store_v_angle                   ; $008E7C ; first frame
        MOVEQ   #$00,D3                         ; $008E7E
        TST.W  D0                               ; $008E80
        BMI.S  .v_angle_negative                ; $008E82
        MOVE.W  (-16128).W,D3                   ; $008E84 ; prev V angle
        BPL.S  .v_blend_long                    ; $008E88 ; same sign
.v_check_quadrant:
        CMPI.W  #$C000,D0                       ; $008E8A
        BCC.S  .v_blend_word                    ; $008E8E
        CMPI.W  #$4000,D0                       ; $008E90
        BCC.S  .v_blend_long                    ; $008E94
.v_blend_word:
        ADD.W   D3,D0                           ; $008E96 ; word avg
        ASR.W  #1,D0                            ; $008E98
        BRA.S  .store_v_angle                   ; $008E9A
.v_angle_negative:
        MOVE.W  (-16128).W,D3                   ; $008E9C ; prev V angle
        BPL.S  .v_check_quadrant                ; $008EA0
.v_blend_long:
        ANDI.L  #$0000FFFF,D0                   ; $008EA2 ; unsigned blend
        ADD.L   D3,D0                           ; $008EA8
        ASR.L  #1,D0                            ; $008EAA ; /2
.store_v_angle:
        MOVE.W  D0,(-16192).W                   ; $008EAC ; output V angle
        MOVE.W  D0,(-16128).W                   ; $008EB0 ; save for next frame
        RTS                                     ; $008EB4
