; ============================================================================
; lateral_drift_velocity_processing_00987e — Lateral Drift Velocity Processing (A)
; ROM Range: $00987E-$0099AA (300 bytes)
; Processes lateral drift/slide physics. Reduces grip based on steering
; magnitude, handles slip angle detection from +$4C with threshold $0037,
; applies force integration to +$94 (lateral velocity). Triggers spin-out
; via flag OR on +$02 with sound $B2 when drift exceeds limit. Natural
; damping decays velocity toward zero with sign preservation.
;
; Entry: A0 = entity pointer
; Uses: D0, D1, D2, A0
; Object fields: +$02 flags, +$10 drag, +$3C heading, +$4C slip angle,
;   +$62 collision, +$6A lateral collision, +$78 grip, +$8C lateral flag,
;   +$92 slide, +$94 lateral velocity, +$96 lateral display
; Confidence: high
; ============================================================================

; --- Grip reduction from |steering| * drag ---
lateral_drift_velocity_processing_00987e:
        MOVE.W  (-16384).W,D0                   ; $00987E  ; D0 = steering input
        BPL.S  .abs_steering_done               ; $009882
        NEG.W  D0                               ; $009884  ; |steering|
.abs_steering_done:
        MULS    $0010(A0),D0                    ; $009886  ; * drag coefficient
        ASR.W  #8,D0                            ; $00988A  ; normalize
        MOVE.W  $0078(A0),D1                    ; $00988C  ; current grip
        SUB.W   D0,D1                           ; $009890  ; reduce grip
        CMPI.W  #$007F,D1                       ; $009892  ; min grip = 127
        BGE.S  .clamp_grip_lower                ; $009896
        MOVEQ   #$7F,D1                         ; $009898
.clamp_grip_lower:
        MOVE.W  D1,$0078(A0)                    ; $00989A  ; store updated grip

; --- Check slide/collision state → damp if active ---
        CLR.B  (-15589).W                       ; $00989E  ; clear slide indicator
        MOVE.W  $0092(A0),D0                    ; $0098A2  ; slide state
        ADD.W  $0062(A0),D0                     ; $0098A6  ; + collision state
        BNE.W  .natural_damping                 ; $0098AA  ; active → damp

; --- Slip angle detection: threshold = $37 (55 deg) ---
        MOVE.W  $004C(A0),D0                    ; $0098AE  ; D0 = slip angle
        MOVE.W  D0,D1                           ; $0098B2
        BPL.S  .abs_slip_done                   ; $0098B4
        NEG.W  D1                               ; $0098B6  ; |slip|
.abs_slip_done:
        CMPI.W  #$0037,D1                       ; $0098B8  ; below threshold?
        BLE.W  .natural_damping                 ; $0098BC  ; no drift force

; --- Force integration: slip / divisor * grip_loss ---
        MOVE.W  $0094(A0),D1                    ; $0098C0  ; |lateral velocity|
        BPL.S  .abs_lateral_done                ; $0098C4
        NEG.W  D1                               ; $0098C6
.abs_lateral_done:
        EXT.L   D0                              ; $0098C8
        DIVS    (-16146).W,D0                   ; $0098CA  ; slip / drift divisor
        CMP.W  (-16144).W,D1                    ; $0098CE  ; high velocity?
        BGT.S  .high_velocity_slide             ; $0098D2  ; yes → different path

; --- Low-velocity drift: force = slip * (512-grip) ---
        MOVE.W  #$0200,D2                       ; $0098D4  ; grip complement base
        SUB.W  $0078(A0),D2                     ; $0098D8  ; D2 = 512 - grip
        MULS    D2,D0                           ; $0098DC  ; slip * grip_loss
        ASR.L  #8,D0                            ; $0098DE  ; normalize
        ADD.W  D0,$0094(A0)                     ; $0098E0  ; integrate force
        MOVE.W  $0094(A0),D0                    ; $0098E4
        ASR.W  #1,D0                            ; $0098E8  ; display = vel/2
        MOVE.W  D0,$0096(A0)                    ; $0098EA
        BRA.W  .done                            ; $0098EE

; --- High-velocity slide: stronger drift + heading corr ---
.high_velocity_slide:
        MOVE.B  #$01,(-15589).W                 ; $0098F2  ; set slide indicator
        ASR.W  #2,D0                            ; $0098F8  ; D0 = slip/4
        MOVE.W  D0,D1                           ; $0098FA
        ASR.W  #1,D1                            ; $0098FC  ; D1 = slip/8
        ADD.W   D1,D0                           ; $0098FE  ; D0 = slip*3/8
        ADD.W  D0,$0094(A0)                     ; $009900  ; integrate
        MOVE.W  $0094(A0),D0                    ; $009904
        MOVE.W  D0,D1                           ; $009908
        BPL.S  .abs_vel_for_spin                ; $00990A
        NEG.W  D1                               ; $00990C  ; |lateral vel|
.abs_vel_for_spin:
        MOVE.W  D0,$0096(A0)                    ; $00990E  ; display = full vel

; --- Heading correction proportional to lateral vel ---
        MULS    (-16138).W,D0                   ; $009912  ; * heading corr coeff
        ASR.L  #8,D0                            ; $009916
        SUB.W  D0,$003C(A0)                     ; $009918  ; adjust heading

; --- Spin-out trigger if |vel| >= threshold ---
        CMP.W  (-16142).W,D1                    ; $00991C  ; spin-out limit
        BLT.W  .done                            ; $009920  ; below → done
        MOVE.W  $006A(A0),D2                    ; $009924  ; lateral collision
        ADD.W  $008C(A0),D2                     ; $009928  ; + lateral flag
        BNE.W  .done                            ; $00992C  ; already colliding
        MOVE.W  #$2000,D2                       ; $009930  ; spin-left flag
        TST.W  $0094(A0)                        ; $009934
        BMI.S  .spinout_flag_selected           ; $009938
        MOVE.W  #$1000,D2                       ; $00993A  ; spin-right flag
.spinout_flag_selected:
        MOVE.B  #$B2,(-14172).W                 ; $00993E  ; spin-out sound $B2
        OR.W   D2,$0002(A0)                     ; $009944  ; set spin flag
        CLR.B  (-15589).W                       ; $009948  ; clear slide indicator
        BRA.W  .done                            ; $00994C

; --- Natural damping: decay lateral vel toward zero ---
.natural_damping:
        MOVE.W  $0094(A0),D0                    ; $009950  ; lateral velocity
        MOVE.W  D0,D1                           ; $009954  ; save original
        BMI.S  .negative_vel                    ; $009956
; --- Clamp positive to min $100 for drag calc ---
        CMPI.W  #$0100,D0                       ; $009958
        BGT.S  .apply_drag                      ; $00995C
        MOVE.W  #$0100,D0                       ; $00995E  ; min drag input
        BRA.S  .apply_drag                      ; $009962
; --- Clamp negative to max -$100 for drag calc ---
.negative_vel:
        CMPI.W  #$FF00,D0                       ; $009964  ; = -$100
        BLT.S  .apply_drag                      ; $009968
        MOVE.W  #$FF00,D0                       ; $00996A
.apply_drag:
        MOVE.W  D0,D1                           ; $00996E  ; D1 = clamped vel
        MULS    (-16140).W,D0                   ; $009970  ; * lateral drag coeff
        ASR.L  #8,D0                            ; $009974  ; normalize
        SUB.W  D0,$0094(A0)                     ; $009976  ; apply drag
; --- Zero-crossing: if drag overshot, clamp to 0 ---
        MOVE.W  $0094(A0),D2                    ; $00997A
        EOR.W   D2,D0                           ; $00997E  ; sign changed?
        BPL.S  .check_zero_crossing             ; $009980  ; same sign → ok
        CLR.W  $0094(A0)                        ; $009982  ; crossed zero → stop
.check_zero_crossing:
        MOVE.W  $0094(A0),D0                    ; $009986
        MOVE.W  D0,$0096(A0)                    ; $00998A  ; display = actual vel

; --- Check if damping settled to rest ---
        TST.W  D1                               ; $00998E  ; normalize signs
        BGE.S  .signs_normalized                ; $009990
        NEG.W  D0                               ; $009992
        NEG.W  D1                               ; $009994
.signs_normalized:
        CMP.W  D0,D1                            ; $009996  ; original > current?
        BLT.S  .done                            ; $009998  ; no → still decaying
        TST.W  D0                               ; $00999A  ; vel < 0?
        BLT.S  .done                            ; $00999C
        CMPI.W  #$000F,D0                       ; $00999E  ; vel < 16?
        BGT.S  .done                            ; $0099A2
        CLR.W  $0094(A0)                        ; $0099A4  ; settled → zero out
.done:
        RTS                                     ; $0099A8
