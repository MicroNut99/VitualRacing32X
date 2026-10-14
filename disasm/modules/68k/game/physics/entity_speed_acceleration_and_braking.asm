; ============================================================================
; entity_speed_acceleration_and_braking — Entity Speed Acceleration and Braking
; ROM Range: $009182-$009300 (382 bytes)
; Manages entity longitudinal speed using acceleration/braking tables at
; $0088A1F0 and $00939EDE. Applies multiplicative acceleration when
; accelerating, division-based deceleration when braking. Speed index
; +$7A controls gear/phase, speed value at +$74. Triggers sound $B4 on
; speed threshold events. Clamps final speed delta to +/-$0400.
;
; Entry: A0 = entity pointer
; Uses: D0, D1, D2, A0, A1
; Object fields: +$04 speed, +$6A collision, +$74 raw speed, +$7A speed
;   index, +$7E target speed, +$82 sound timer, +$84 brake timer,
;   +$8C lateral flag, +$AE table offset
; Confidence: high
; ============================================================================

; --- Skip if lateral collision or sliding ---
entity_speed_acceleration_and_braking:
        MOVE.W  $008C(A0),D1                    ; $009182  ; lateral flag
        ADD.W  $006A(A0),D1                     ; $009186  ; + collision state
        DC.W    $6600,$0174         ; BNE.W  $009300; $00918A  ; skip → end of func

; --- Check surface allows accel/brake ---
        TST.B  (-15601).W                       ; $00918E  ; on drivable surface?
        BEQ.W  .coast_or_natural_accel          ; $009192  ; no → coast only

; --- Check per-segment accel permission table ---
        MOVE.W  $00AE(A0),D0                    ; $009196  ; table offset
        ADD.W   D0,D0                           ; $00919A  ; word index
        LEA     (-16292).W,A1                   ; $00919C  ; segment permission tbl
        CMPI.W  #$0001,$00(A1,D0.W)             ; $0091A0  ; accel blocked?
        BEQ.W  .coast_or_natural_accel          ; $0091A6  ; yes → coast

; === Acceleration (gas button held) ===
        BTST    #1,(-13965).W                   ; $0091AA  ; gas button?
        BEQ.S  .check_brake                     ; $0091B0
        MOVE.W  $007A(A0),D2                    ; $0091B2  ; speed index (gear)
        CMPI.W  #$0006,D2                       ; $0091B6  ; max gear = 6?
        BGE.W  .clamp_speed_delta               ; $0091BA  ; at top → done

; --- Multiply speed by gear ratio (acceleration curve) ---
        MOVE.W  $0074(A0),D1                    ; $0091BE  ; raw speed
        LEA     $0088A1F0,A1                    ; $0091C2  ; gear ratio table
        ADD.W   D2,D2                           ; $0091C8  ; word index
        MULS    $00(A1,D2.W),D1                 ; $0091CA  ; speed * gear_ratio
        LSR.L  #8,D1                            ; $0091CE  ; normalize
        MOVE.W  D1,$0074(A0)                    ; $0091D0  ; store new speed
        ADDQ.W  #1,$007A(A0)                    ; $0091D4  ; advance gear

; --- Gear shift sound at speed $1F40 (8000) in low gears ---
        CMPI.W  #$1F40,$0074(A0)                ; $0091D8  ; speed >= 8000?
        BLT.S  .accel_done                      ; $0091DE
        CMPI.W  #$0004,$007A(A0)                ; $0091E0  ; gear < 4?
        BGE.S  .accel_done                      ; $0091E6
        TST.W  $0082(A0)                        ; $0091E8  ; sound timer active?
        BNE.S  .accel_done                      ; $0091EC
        MOVE.W  #$000F,$0082(A0)                ; $0091EE  ; 15-frame timer
        MOVE.B  #$B4,(-14172).W                 ; $0091F4  ; tire squeal $B4
.accel_done:
        BRA.W  .clamp_speed_delta               ; $0091FA

; === Braking (brake button held) ===
.check_brake:
        BTST    #0,(-13965).W                   ; $0091FE  ; brake button?
        BEQ.W  .clamp_speed_delta               ; $009204  ; no → skip
        TST.W  $007A(A0)                        ; $009208  ; gear > 0?
        BLE.W  .clamp_speed_delta               ; $00920C  ; no → skip

; --- Divide speed by gear ratio (deceleration) ---
        SUBQ.W  #1,$007A(A0)                    ; $009210  ; downshift
        MOVE.W  $0074(A0),D1                    ; $009214  ; raw speed
        EXT.L   D1                              ; $009218
        LSL.L  #8,D1                            ; $00921A  ; 8.8 fixed-point
        LEA     $0088A1F0,A1                    ; $00921C  ; gear ratio table
        MOVE.W  $007A(A0),D2                    ; $009222  ; new gear index
        ADD.W   D2,D2                           ; $009226  ; word index
        DIVU    $00(A1,D2.W),D1                 ; $009228  ; speed / gear_ratio
        MOVE.W  D1,$0074(A0)                    ; $00922C  ; store braked speed
        CMPI.W  #$4268,D1                       ; $009230  ; max speed 17000
        BLE.W  .clamp_speed_delta               ; $009234
        MOVE.W  #$4268,$0074(A0)                ; $009238  ; clamp to max
        TST.W  $0084(A0)                        ; $00923E  ; brake timer active?
        BNE.S  .brake_timer_active              ; $009242
        MOVE.W  #$000A,$0084(A0)                ; $009244  ; 10-frame timer
.brake_timer_active:
        MOVE.W  #$00FF,$0010(A0)                ; $00924A  ; max drag on overspeed
        BRA.W  .clamp_speed_delta               ; $009250

; === Coasting / natural acceleration (no input) ===
.coast_or_natural_accel:
        MOVE.W  $0074(A0),D2                    ; $009254  ; raw speed
        MOVE.W  $007A(A0),D1                    ; $009258  ; gear index
        ADD.W   D1,D1                           ; $00925C  ; word index

; --- Check if speed exceeds gear's natural threshold ---
        TST.W  $0004(A0)                        ; $00925E  ; base speed != 0?
        BEQ.W  .check_decelerate                ; $009262  ; no speed → decel
        LEA     $0088A1E2,A1                    ; $009266  ; natural accel thresholds
        CMP.W  $00(A1,D1.W),D2                  ; $00926C  ; above threshold?
        BLE.W  .check_decelerate                ; $009270  ; no → check decel

; --- Natural upshift: multiply by gear ratio ---
        LEA     $0088A1F0,A1                    ; $009274  ; gear ratio table
        MULS    $00(A1,D1.W),D2                 ; $00927A  ; speed * gear_ratio
        LSR.L  #8,D2                            ; $00927E  ; normalize
        MOVE.W  D2,$0074(A0)                    ; $009280  ; store new speed
        ADDQ.W  #1,$007A(A0)                    ; $009284  ; advance gear

; --- Natural shift sound trigger ---
        CMPI.W  #$1F40,$0074(A0)                ; $009288  ; speed >= 8000?
        BLT.S  .natural_accel_done              ; $00928E
        CMPI.W  #$0004,$007A(A0)                ; $009290  ; gear < 4?
        BGE.S  .natural_accel_done              ; $009296
        TST.W  $0082(A0)                        ; $009298  ; timer active?
        BNE.S  .natural_accel_done              ; $00929C
        MOVE.W  #$000F,$0082(A0)                ; $00929E  ; 15-frame timer
        MOVE.B  #$B4,(-14172).W                 ; $0092A4  ; tire squeal $B4
.natural_accel_done:
        BRA.W  .clamp_speed_delta               ; $0092AA

; === Deceleration: speed below gear's lower threshold ===
.check_decelerate:
        LEA     $00939EDE,A1                    ; $0092AE  ; decel threshold table
        CMP.W  $00(A1,D1.W),D2                  ; $0092B4  ; below threshold?
        BGE.W  .clamp_speed_delta               ; $0092B8  ; no → done

; --- Natural downshift: divide by prev gear ratio ---
        SUBQ.W  #1,$007A(A0)                    ; $0092BC  ; downshift
        EXT.L   D2                              ; $0092C0
        LSL.L  #8,D2                            ; $0092C2  ; 8.8 fixed-point
        LEA     $0088A1F0,A1                    ; $0092C4  ; gear ratio table
        DIVS    -$02(A1,D1.W),D2                ; $0092CA  ; / prev gear ratio
        MOVE.W  D2,$0074(A0)                    ; $0092CE  ; store decel speed
        TST.W  $0084(A0)                        ; $0092D2  ; brake timer active?
        BNE.S  .clamp_speed_delta               ; $0092D6
        MOVE.W  #$000A,$0084(A0)                ; $0092D8  ; 10-frame timer

; === Clamp speed delta to [-$400, +$400] per frame ===
.clamp_speed_delta:
        MOVE.W  $0074(A0),D1                    ; $0092DE  ; raw speed
        SUB.W  $007E(A0),D1                     ; $0092E2  ; delta = raw - target
        CMPI.W  #$0400,D1                       ; $0092E6  ; max +1024/frame
        BLE.S  .check_min_clamp                 ; $0092EA
        MOVE.W  #$0400,D1                       ; $0092EC
.check_min_clamp:
        CMPI.W  #$FC00,D1                       ; $0092F0  ; min -1024/frame
        BGE.S  .apply_delta                     ; $0092F4
        MOVE.W  #$FC00,D1                       ; $0092F6
.apply_delta:
        ADD.W  D1,$007E(A0)                     ; $0092FA  ; target += clamped delta
        RTS                                     ; $0092FE
