; ============================================================================
; steering_input_processing_and_velocity_update — Steering Input Processing and Velocity Update
; ROM Range: $0094F4-$00961E (298 bytes)
; Data prefix (2 bytes) at start. Reads controller button bits for left/right
; and up/down input, computes steering direction with acceleration and
; deadzone. Smooths steering velocity with damping, clamps to +/-$7F range.
; Applies integrated steering to entity field +$8E. Manages lateral drift
; accumulator at +$AA.
;
; Entry: A0 = entity pointer
; Uses: D0, D1, D2, D3, A0, A1
; Object fields: +$8E steering velocity, +$94 drift rate, +$AA drift accum
; Confidence: high
; ============================================================================

; --- Data prefix: lookup table for steering acceleration ---
steering_input_processing_and_velocity_update:
        DC.W    $FFE8                           ; $0094F4  ; table: [-24, 24, 0]
        ORI.B  #$18,D0                          ; $0094F6  ; (table data, not code)

; --- Copy previous input state, read new input ---
        MOVE.B  (-15616).W,(-15615).W           ; $0094FA  ; prev = current
        MOVE.B  (-13967).W,(-15616).W           ; $009500  ; current = new input

; --- Resolve button mapping (swappable L/R) ---
        MOVEQ   #$02,D2                         ; $009506  ; D2 = left bit index
        MOVEQ   #$03,D3                         ; $009508  ; D3 = right bit index
        BTST    #7,(-600).W                     ; $00950A  ; button swap flag?
        BEQ.S  .buttons_resolved                ; $009510
        EXG     D2,D3                           ; $009512  ; swap L/R mapping
.buttons_resolved:

; --- Read directional input: D0=L/R, D1=U/D ---
        LEA     (-15616).W,A1                   ; $009514  ; A1 = input buffer
        MOVEQ   #$00,D0                         ; $009518  ; horizontal = 0
        MOVEQ   #$00,D1                         ; $00951A  ; vertical = 0
        BTST    D2,$0001(A1)                    ; $00951C  ; left pressed?
        BEQ.S  .check_right                     ; $009520
        MOVEQ   #$01,D0                         ; $009522  ; left = +1
.check_right:
        BTST    D3,$0001(A1)                    ; $009524  ; right pressed?
        BEQ.S  .check_up                        ; $009528
        SUBQ.W  #1,D0                           ; $00952A  ; right = -1
.check_up:
        BTST    D2,(A1)                         ; $00952C  ; up pressed?
        BEQ.S  .check_down                      ; $00952E
        MOVEQ   #$01,D1                         ; $009530  ; up = +1
.check_down:
        BTST    D3,(A1)                         ; $009532  ; down pressed?
        BEQ.S  .input_resolved                  ; $009534
        SUBQ.W  #1,D1                           ; $009536  ; down = -1
.input_resolved:

; --- A1 → accel lookup table (data prefix at +2) ---
        lea     steering_input_processing_and_velocity_update+2(pc),a1; $43FA $FFBC

; --- Direction change detection ---
        CMP.W  (-16378).W,D1                    ; $00953C  ; same as last frame?
        BEQ.S  .same_direction                  ; $009540

; --- New direction: set initial steering velocity ---
        MOVE.W  D1,(-16378).W                   ; $009542  ; store new direction
        MOVE.W  D1,D2                           ; $009546
        ADD.W   D2,D2                           ; $009548  ; word index
        MOVE.W  $00(A1,D2.W),D2                 ; $00954A  ; table lookup
        MOVE.W  D2,(-16384).W                   ; $00954E  ; set steering vel
        LSL.W  #8,D2                            ; $009552  ; scale to 8.8
        MOVE.W  D2,$008E(A0)                    ; $009554  ; store to entity
        BRA.S  .clamp_velocity                  ; $009558

; --- Same direction: apply damping or acceleration ---
.same_direction:
        TST.W  D1                               ; $00955A  ; input = 0?
        BNE.S  .nonzero_input                   ; $00955C

; --- No input: apply centering damping ---
        MOVE.W  (-16384).W,D2                   ; $00955E  ; current steering vel
        BEQ.S  .apply_damping                   ; $009562  ; already zero
        BPL.S  .apply_positive_damp             ; $009564
        MOVEQ   #-$02,D2                        ; $009566  ; damp index = -2
        BRA.S  .apply_damping                   ; $009568
.apply_positive_damp:
        MOVEQ   #$02,D2                         ; $00956A  ; damp index = +2
.apply_damping:
        MOVE.W  $00(A1,D2.W),D2                 ; $00956C  ; damp amount from table
        SUB.W  D2,(-16384).W                    ; $009570  ; reduce steering vel
        BRA.S  .clamp_velocity                  ; $009574

; --- Continued input: accelerate with countersteer decay ---
.nonzero_input:
        MOVE.W  D1,(-16378).W                   ; $009576  ; store direction
        MOVE.W  D1,D2                           ; $00957A
        ADD.W   D2,D2                           ; $00957C  ; word index
        MOVE.W  $00(A1,D2.W),D2                 ; $00957E  ; accel from table
        TST.W  (-14136).W                       ; $009582  ; countersteer flag?
        BEQ.S  .add_acceleration                ; $009586  ; no → full accel
; --- Countersteering: halve accel, decay drift ---
        MOVE.W  $0094(A0),D0                    ; $009588  ; drift rate
        EOR.W   D2,D0                           ; $00958C  ; same sign as steer?
        BMI.S  .add_acceleration                ; $00958E  ; opposite → full accel
        ASR.W  #1,D2                            ; $009590  ; halve accel
        MOVE.W  $0094(A0),D0                    ; $009592  ; drift rate
        ASR.W  #3,D0                            ; $009596  ; drift/8
        SUB.W  D0,$0094(A0)                     ; $009598  ; decay drift
.add_acceleration:
        ADD.W  D2,(-16384).W                    ; $00959C  ; add accel to vel

; --- Clamp steering velocity to [-$7F, +$7F] ---
.clamp_velocity:
        CMPI.W  #$007F,(-16384).W               ; $0095A0  ; max = +127
        BLE.S  .check_lower_clamp               ; $0095A6
        MOVE.W  #$007F,(-16384).W               ; $0095A8
.check_lower_clamp:
        CMPI.W  #$FF81,(-16384).W               ; $0095AE  ; min = -127
        BGE.S  .apply_deadzone                  ; $0095B4
        MOVE.W  #$FF81,(-16384).W               ; $0095B6

; --- Deadzone: |vel| < 24 → zero steering ---
.apply_deadzone:
        MOVE.W  (-16384).W,D2                   ; $0095BC  ; current steering vel
        MOVE.W  D2,D0                           ; $0095C0
        BPL.S  .check_deadzone_threshold        ; $0095C2
        NEG.W  D0                               ; $0095C4  ; |vel|
        BVC.S  .integrate_steering              ; $0095C6  ; overflow = max neg
.check_deadzone_threshold:
        CMPI.W  #$0018,D0                       ; $0095C8  ; deadzone = 24
        BGE.S  .integrate_steering              ; $0095CC  ; above → keep
        CLR.W  (-16384).W                       ; $0095CE  ; below → zero

; --- Integrate: new_steer = (vel*256 + old_steer) / 2 ---
.integrate_steering:
        EXT.L   D2                              ; $0095D2
        LSL.L  #8,D2                            ; $0095D4  ; vel → 8.8 fixed-point
        MOVE.W  $008E(A0),D1                    ; $0095D6  ; old steering
        EXT.L   D1                              ; $0095DA
        ADD.L   D1,D2                           ; $0095DC  ; sum
        ASR.L  #1,D2                            ; $0095DE  ; average (smoothing)

; --- Track drift accumulator from steering delta ---
        MOVE.L  D2,D3                           ; $0095E0
        SUB.L   D1,D3                           ; $0095E2  ; D3 = steer delta
        TST.W  D3                               ; $0095E4
        BPL.S  .abs_delta_done                  ; $0095E6
        NEG.W  D3                               ; $0095E8  ; |delta|
.abs_delta_done:
        ASR.W  #8,D3                            ; $0095EA  ; normalize from 8.8
        ADD.W  $00AA(A0),D3                     ; $0095EC  ; accumulate drift
        CMPI.W  #$00C8,D3                       ; $0095F0  ; max drift = 200
        BLE.S  .check_drift_lower               ; $0095F4
        MOVE.W  #$00C8,D3                       ; $0095F6
.check_drift_lower:
        CMPI.W  #$0000,D3                       ; $0095FA  ; min drift = 0
        BGE.S  .store_drift                     ; $0095FE
        MOVE.W  #$0000,D3                       ; $009600
.store_drift:
        MOVE.W  D3,$00AA(A0)                    ; $009604  ; store drift accum

; --- Final deadzone on integrated steering ---
        MOVE.W  D2,D1                           ; $009608
        BPL.S  .check_final_deadzone            ; $00960A
        NEG.W  D1                               ; $00960C  ; |steering|
        BVS.S  .store_steering                  ; $00960E  ; overflow → keep
.check_final_deadzone:
        CMPI.W  #$0018,D1                       ; $009610  ; deadzone = 24
        BGE.S  .store_steering                  ; $009614
        MOVEQ   #$00,D2                         ; $009616  ; below → zero
.store_steering:
        MOVE.W  D2,$008E(A0)                    ; $009618  ; store steering vel
        RTS                                     ; $00961C
