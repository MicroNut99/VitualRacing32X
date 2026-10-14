; ============================================================================
; lateral_drift_velocity_processing_0099aa — Lateral Drift Velocity Processing (B)
; ROM Range: $0099AA-$009B12 (360 bytes)
; Variant of lateral_drift_velocity_processing_00987e with speed-dependent grip reduction and AI boost.
; Same lateral drift physics: slip detection from +$4C, force integration
; to +$94, spin-out trigger with sound $B2. Writes final viewport scaling
; values to $FF617A/$FF618E.
;
; Entry: A0 = entity pointer
; Uses: D0, D1, D2, D6, D7, A0
; Object fields: +$02 flags, +$04 speed, +$0E force, +$10 drag,
;   +$3C heading, +$4C slip angle, +$62 collision, +$6A lateral collision,
;   +$78 grip, +$80 effect timer, +$8C lateral flag, +$92 slide,
;   +$94 lateral velocity, +$96 lateral display
; Confidence: high
; ============================================================================

; --- Init viewport scale values ---
lateral_drift_velocity_processing_0099aa:
        MOVE.W  #$00B5,D6                       ; $0099AA  ; viewport left = 181
        MOVE.W  D6,D7                           ; $0099AE  ; viewport right = 181

; --- Compute grip reduction from steering * drag ---
        MOVE.W  (-16384).W,D0                   ; $0099B0  ; D0 = steering input
        BPL.S  .abs_steering_done               ; $0099B4
        NEG.W  D0                               ; $0099B6  ; |steering|
.abs_steering_done:
        MULS    $0010(A0),D0                    ; $0099B8  ; * drag coefficient
        ASR.L  #7,D0                            ; $0099BC  ; normalize 8.8

; --- AI boost: extra grip loss at high speed ---
        MOVEQ   #$00,D1                         ; $0099BE
        CMPI.W  #$00C8,$0004(A0)                ; $0099C0  ; speed > 200?
        BLE.S  .grip_reduction_done             ; $0099C6
        BTST    #4,(-13967).W                   ; $0099C8  ; AI control flag?
        BEQ.S  .grip_reduction_done             ; $0099CE
        MOVE.W  #$00FF,D1                       ; $0099D0  ; 255 - force param
        SUB.W  $000E(A0),D1                     ; $0099D4
        ASL.W  #3,D1                            ; $0099D8  ; *8 = AI boost amount
.grip_reduction_done:

; --- Clamp grip to [$40, $FF] ---
        ADD.W   D1,D0                           ; $0099DA  ; total grip loss
        MOVE.W  $0078(A0),D1                    ; $0099DC  ; current grip
        SUB.W   D0,D1                           ; $0099E0  ; reduce grip
        CMPI.W  #$00FF,D1                       ; $0099E2  ; max grip 255
        BLE.S  .check_grip_lower                ; $0099E6
        MOVE.W  #$00FF,D1                       ; $0099E8
.check_grip_lower:
        CMPI.W  #$0040,D1                       ; $0099EC  ; min grip 64
        BGE.S  .store_grip                      ; $0099F0
        MOVE.W  #$0040,D1                       ; $0099F2
.store_grip:
        MOVE.W  D1,$0078(A0)                    ; $0099F6

; --- Check if slide or collision active → damp instead ---
        MOVE.W  $0092(A0),D0                    ; $0099FA  ; slide state
        ADD.W  $0062(A0),D0                     ; $0099FE  ; + collision state
        BNE.W  .natural_damping                 ; $009A02  ; active → damp

; --- Slip angle detection: threshold = $37 (55 deg) ---
        MOVE.W  $004C(A0),D0                    ; $009A06  ; D0 = slip angle
        MOVE.W  D0,D1                           ; $009A0A
        BPL.S  .abs_slip_done                   ; $009A0C
        NEG.W  D1                               ; $009A0E  ; |slip|
.abs_slip_done:
        CMPI.W  #$0037,D1                       ; $009A10  ; below threshold?
        BLE.W  .natural_damping                 ; $009A14  ; no drift force

; --- Lateral force integration: slip * (512-grip) / divisor ---
        MOVE.W  $0094(A0),D1                    ; $009A18  ; |lateral velocity|
        BPL.S  .abs_lateral_done                ; $009A1C
        NEG.W  D1                               ; $009A1E
.abs_lateral_done:
        MOVE.W  #$0200,D2                       ; $009A20  ; 512 = grip complement base
        SUB.W  $0078(A0),D2                     ; $009A24  ; D2 = 512 - grip
        MULS    D2,D0                           ; $009A28  ; slip * grip_loss
        ASR.L  #8,D0                            ; $009A2A  ; normalize
        DIVS    (-16146).W,D0                   ; $009A2C  ; / drift divisor
        CMP.W  (-16144).W,D1                    ; $009A30  ; high velocity?
        BLE.S  .apply_force                     ; $009A34
        ASR.W  #1,D0                            ; $009A36  ; halve at high vel
.apply_force:
        ADD.W  D0,$0094(A0)                     ; $009A38  ; integrate force
        MOVE.W  $0094(A0),D0                    ; $009A3C  ; updated lateral vel
        MOVE.W  D0,D2                           ; $009A40
        ADD.W   D2,D2                           ; $009A42  ; display = 2x actual
        MOVE.W  D2,$0096(A0)                    ; $009A44

; --- Spin-out check: |lateral vel| >= 256 → viewport shift ---
        MOVE.W  D0,D1                           ; $009A48
        BPL.S  .abs_vel_for_spin                ; $009A4A
        NEG.W  D1                               ; $009A4C
.abs_vel_for_spin:
        CMPI.W  #$0100,D1                       ; $009A4E  ; spin threshold
        BLT.S  .apply_heading_correction        ; $009A52
        MOVEQ   #$7F,D2                         ; $009A54  ; viewport shift = 127
        TST.W  D0                               ; $009A56
        BMI.S  .adjust_viewport                 ; $009A58  ; drift left → shift left
        NEG.W  D2                               ; $009A5A  ; drift right → shift right
.adjust_viewport:
        ADD.W   D2,D6                           ; $009A5C  ; adjust left edge
        SUB.W   D2,D7                           ; $009A5E  ; adjust right edge
        CMPI.W  #$000B,$0080(A0)                ; $009A60  ; effect timer < 11?
        BGE.S  .apply_heading_correction        ; $009A66
        ADDQ.W  #4,$0080(A0)                    ; $009A68  ; increment timer

; --- Heading correction from lateral velocity ---
.apply_heading_correction:
        MULS    (-16138).W,D0                   ; $009A6C  ; * heading correction coeff
        ASR.L  #8,D0                            ; $009A70
        SUB.W  D0,$003C(A0)                     ; $009A72  ; adjust heading

; --- Spin-out trigger if above spin limit ---
        CMP.W  (-16142).W,D1                    ; $009A76  ; spin-out threshold
        BLT.W  .write_viewport                  ; $009A7A  ; below → done
        MOVE.W  $006A(A0),D2                    ; $009A7E  ; lateral collision
        ADD.W  $008C(A0),D2                     ; $009A82  ; + lateral flag
        BNE.W  .write_viewport                  ; $009A86  ; already colliding
        MOVE.W  #$2000,D2                       ; $009A8A  ; spin-left flag
        TST.W  $0094(A0)                        ; $009A8E
        BMI.S  .spinout_flag_selected           ; $009A92
        MOVE.W  #$1000,D2                       ; $009A94  ; spin-right flag
.spinout_flag_selected:
        MOVE.B  #$B2,(-14172).W                 ; $009A98  ; spin-out sound $B2
        OR.W   D2,$0002(A0)                     ; $009A9E  ; set spin flag
        BRA.W  .write_viewport                  ; $009AA2

; --- Natural damping: decay lateral vel toward zero ---
.natural_damping:
        MOVE.W  $0094(A0),D0                    ; $009AA6  ; lateral velocity
        MOVE.W  D0,D1                           ; $009AAA  ; save original
        BMI.S  .negative_vel                    ; $009AAC
; --- Clamp positive vel to min $200 for drag calc ---
        CMPI.W  #$0200,D0                       ; $009AAE
        BGT.S  .apply_drag                      ; $009AB2
        MOVE.W  #$0200,D0                       ; $009AB4  ; min drag input
        BRA.S  .apply_drag                      ; $009AB8
; --- Clamp negative vel to max -$200 for drag calc ---
.negative_vel:
        CMPI.W  #$FE00,D0                       ; $009ABA  ; = -$200
        BLT.S  .apply_drag                      ; $009ABE
        MOVE.W  #$FE00,D0                       ; $009AC0
.apply_drag:
        MOVE.W  D0,D1                           ; $009AC4  ; D1 = clamped vel
        MULS    (-16140).W,D0                   ; $009AC6  ; * lateral drag coeff
        ASR.L  #8,D0                            ; $009ACA  ; normalize
        SUB.W  D0,$0094(A0)                     ; $009ACC  ; apply drag
; --- Zero-crossing detection: if drag overshot, clamp to 0 ---
        MOVE.W  $0094(A0),D2                    ; $009AD0
        EOR.W   D2,D0                           ; $009AD4  ; sign changed?
        BPL.S  .check_zero_crossing             ; $009AD6  ; same sign → ok
        CLR.W  $0094(A0)                        ; $009AD8  ; crossed zero → stop
.check_zero_crossing:
        MOVE.W  $0094(A0),D0                    ; $009ADC
        MOVE.W  D0,D2                           ; $009AE0
        ASR.W  #1,D2                            ; $009AE2  ; D2 = vel/2
        ADD.W   D0,D2                           ; $009AE4  ; display = 1.5x actual
        MOVE.W  D2,$0096(A0)                    ; $009AE6

; --- Check if damping has settled velocity to rest ---
        TST.W  D1                               ; $009AEA  ; normalize signs
        BGE.S  .signs_normalized                ; $009AEC
        NEG.W  D0                               ; $009AEE
        NEG.W  D1                               ; $009AF0
.signs_normalized:
        CMP.W  D0,D1                            ; $009AF2  ; original > current?
        BLT.S  .write_viewport                  ; $009AF4  ; no → still decaying
        TST.W  D0                               ; $009AF6  ; vel < 0?
        BLT.S  .write_viewport                  ; $009AF8
        CMPI.W  #$000F,D0                       ; $009AFA  ; vel < 16?
        BGT.S  .write_viewport                  ; $009AFE
        CLR.W  $0094(A0)                        ; $009B00  ; settled → zero out

; --- Write viewport scaling values ---
.write_viewport:
        MOVE.W  D6,$00FF617A                    ; $009B04  ; left viewport scale
        MOVE.W  D7,$00FF618E                    ; $009B0A  ; right viewport scale
        RTS                                     ; $009B10
