; ============================================================================
; entity_force_integration_and_speed_calc — Entity Force Integration and Speed Calculation
; ROM Range: $009300-$009458 (344 bytes)
; Integrates forces on entity: computes drag from speed tables, applies
; directional force from param $000E, subtracts friction/air resistance,
; handles speed overflow with sound trigger $B1/$B4. Computes final display
; speed at +$74 from gear table lookups. Multiple entry points — first
; 18 bytes serve as alternate entry with BRA to mid-function.
;
; Entry: A0 = entity pointer
; Uses: D0, D1, D2, D3, A0, A1, A2
; Object fields: +$04 speed, +$06 display speed, +$0C slope, +$0E force,
;   +$10 drag, +$16 calc speed, +$74 raw speed, +$78 grip, +$7A gear,
;   +$80 sound timer, +$82 brake timer
; Confidence: high
; ============================================================================

; --- Alternate entry: set default force, jump to mid-function ---
entity_force_integration_and_speed_calc:
        MOVE.W  #$FFCD,$000E(A0)                ; $009300  ; force = -51 (default drag)
        MOVE.W  $0074(A0),D2                    ; $009306  ; D2 = raw speed
        MOVE.W  $007A(A0),D1                    ; $00930A  ; D1 = gear index
        ADD.W   D1,D1                           ; $00930E  ; word index
        DC.W    $609C               ; BRA.S  $0092AE; $009310  ; jump to decel table

; --- Main entry: clamp raw speed to [0, $4268] ---
        MOVE.W  $0074(A0),D1                    ; $009312  ; D1 = raw speed
        BGE.S  .clamp_speed_upper               ; $009316
        MOVEQ   #$00,D1                         ; $009318
        BRA.S  .speed_clamped                   ; $00931A
.clamp_speed_upper:
        CMPI.W  #$4268,D1                       ; $00931C  ; max speed = 17000
        BLE.S  .speed_clamped                   ; $009320
        MOVE.W  #$4268,D1                       ; $009322
.speed_clamped:

; --- Drag table lookup: index = speed >> 7 ---
        ASR.W  #7,D1                            ; $009326  ; speed / 128 = table index
        LEA     $0093910E,A1                    ; $009328  ; drag table A
        TST.B  (-15601).W                       ; $00932E  ; check surface type flag
        BNE.S  .table_selected                  ; $009332
        LEA     $00938FCE,A1                    ; $009334  ; drag table B (off-road)
.table_selected:
        ADD.W   D1,D1                           ; $00933A  ; word index
        MOVE.W  $00(A1,D1.W),D2                 ; $00933C  ; D2 = drag coefficient

; --- Apply gear multiplier from gear table ---
        MOVEA.L (-15752).W,A2                   ; $009340  ; A2 = gear table ptr
        MOVE.W  $007A(A0),D3                    ; $009344  ; D3 = gear index
        ADD.W   D3,D3                           ; $009348  ; word index
        MULU    $00(A2,D3.W),D2                 ; $00934A  ; drag * gear_mult
        LSR.L  #5,D2                            ; $00934E  ; fixed-point normalize

; --- Apply directional force from entity param ---
        MULS    $000E(A0),D2                    ; $009350  ; drag * force direction
        ASR.L  #7,D2                            ; $009354  ; fixed-point normalize
        BGT.S  .force_clamped                   ; $009356
        MOVE.L  #$FFFFFE00,D0                   ; $009358  ; min force = -512
        CMP.L  D0,D2                            ; $00935E
        BLT.S  .force_clamped                   ; $009360
        MOVE.L  D0,D2                           ; $009362  ; clamp to min
.force_clamped:

; --- Subtract friction and air resistance ---
        jsr     speed_calc_multiplier_chain(pc); $4EBA $00F2
        MOVE.W  $0016(A0),D1                    ; $009368  ; D1 = calc speed
        EXT.L   D1                              ; $00936C
        LSL.L  #4,D1                            ; $00936E  ; *16 for friction scale
        SUB.L   D1,D2                           ; $009370  ; subtract friction
        MOVE.W  $0010(A0),D1                    ; $009372  ; D1 = drag field
        MULS    #$71C0,D1                       ; $009376  ; air resistance coeff
        ASR.L  #7,D1                            ; $00937A
        SUB.L   D1,D2                           ; $00937C  ; subtract air drag
        BPL.S  .negative_force_doubled          ; $00937E  ; if net force negative...
        ADD.L   D2,D2                           ; $009380  ; ...double decel penalty
.negative_force_doubled:

; --- Speed overflow detection with sound triggers ---
        MOVE.W  #$0100,$0078(A0)                ; $009382  ; reset grip to 1.0 (8.8)
        MOVE.W  (-16148).W,D0                   ; $009388  ; D0 = min speed threshold
        NEG.W  D0                               ; $00938C
        EXT.L   D0                              ; $00938E
        CMP.L  D0,D2                            ; $009390  ; force < -threshold?
        BGT.S  .check_overspeed                 ; $009392
        MOVE.L  D0,D1                           ; $009394
        ADD.L   D1,D1                           ; $009396  ; D1 = 2x threshold
        CMP.L  D1,D2                            ; $009398  ; extreme decel?
        BGT.S  .clamp_to_min                    ; $00939A
; --- Trigger skid sound if speed > 20 and no active timers ---
        MOVE.W  $0080(A0),D1                    ; $00939C  ; sound timer
        OR.W   $008C(A0),D1                     ; $0093A0  ; lateral flag
        BNE.S  .clamp_to_min                    ; $0093A4  ; timer active, skip
        CMPI.W  #$0014,$0004(A0)                ; $0093A6  ; speed > 20?
        BLE.W  .clamp_to_min                    ; $0093AC
        MOVE.W  #$000F,$0080(A0)                ; $0093B0  ; 15-frame sound timer
        MOVE.B  #$B1,(-14172).W                 ; $0093B6  ; trigger skid sound $B1
.clamp_to_min:
        MOVE.L  D0,D2                           ; $0093BC  ; clamp force to min
        BRA.S  .integrate_speed                 ; $0093BE

; --- Overspeed: reduce grip proportional to excess ---
.check_overspeed:
        MOVEQ   #$00,D0                         ; $0093C0
        MOVE.W  (-16150).W,D0                   ; $0093C2  ; D0 = max speed threshold
        CMP.L  D0,D2                            ; $0093C6
        BLE.W  .integrate_speed                 ; $0093C8  ; within limit
        MOVE.L  D2,D1                           ; $0093CC
        SUB.L   D0,D1                           ; $0093CE  ; D1 = excess over max
        ASL.L  #8,D1                            ; $0093D0  ; 8.8 fixed-point
        DIVS    D0,D1                           ; $0093D2  ; ratio = excess/max
        SUB.W  D1,$0078(A0)                     ; $0093D4  ; reduce grip by ratio
        CMPI.W  #$0080,D1                       ; $0093D8  ; cap grip reduction
        BLE.S  .check_tire_squeal               ; $0093DC
        MOVE.W  #$0080,$0078(A0)                ; $0093DE  ; min grip = 0.5 (8.8)
.check_tire_squeal:
        TST.W  $007A(A0)                        ; $0093E4  ; in gear 0?
        BNE.S  .integrate_speed                 ; $0093E8  ; no, skip squeal
        TST.W  $0082(A0)                        ; $0093EA  ; brake timer active?
        BNE.S  .integrate_speed                 ; $0093EE
        MOVE.W  #$000F,$0082(A0)                ; $0093F0  ; 15-frame timer
        MOVE.B  #$B4,(-14172).W                 ; $0093F6  ; tire squeal sound $B4

; --- Integrate force into speed, compute display values ---
.integrate_speed:
        ASR.L  #1,D2                            ; $0093FC  ; force / 2
        MULS    $0078(A0),D2                    ; $0093FE  ; * grip (8.8)
        ASR.L  #7,D2                            ; $009402  ; normalize
        MOVE.W  D2,D1                           ; $009404
        ASR.W  #2,D1                            ; $009406  ; force / 4
        EXT.L   D1                              ; $009408
        DIVS    #$0190,D1                       ; $00940A  ; / 400 = slope increment
        MOVE.W  D1,$000C(A0)                    ; $00940E  ; store slope delta
        ADD.W  D1,$0006(A0)                     ; $009412  ; add to display speed
        BPL.S  .display_speed_positive          ; $009416
        CLR.W  $0006(A0)                        ; $009418  ; floor at 0

; --- Compute raw speed from gear table * display speed ---
.display_speed_positive:
        MOVEA.L (-15752).W,A1                   ; $00941C  ; gear table ptr
        MOVE.W  $007A(A0),D1                    ; $009420  ; gear index
        ADD.W   D1,D1                           ; $009424  ; word index
        MOVE.W  $00(A1,D1.W),D3                 ; $009426  ; D3 = gear multiplier
        MULS    $0006(A0),D3                    ; $00942A  ; * display speed
; --- Multiply D3 by ~21.25 using shift-add chain ---
        ASL.L  #2,D3                            ; $00942E  ; *4
        MOVE.L  D3,D1                           ; $009430  ; D1 = 4x
        ASL.L  #2,D3                            ; $009432  ; *16
        ADD.L   D3,D1                           ; $009434  ; D1 = 20x
        ASL.L  #2,D3                            ; $009436  ; *64
        ADD.L   D3,D1                           ; $009438  ; D1 = 84x
        ASL.L  #3,D3                            ; $00943A  ; *512
        ADD.L   D1,D3                           ; $00943C  ; D3 = 596x
        MOVEQ   #$0C,D1                         ; $00943E
        LSR.L  D1,D3                            ; $009440  ; /4096 => ~0.1455x total
        BGE.S  .clamp_raw_upper                 ; $009442
        MOVEQ   #$00,D3                         ; $009444
.clamp_raw_upper:
        CMPI.L  #$00004268,D3                   ; $009446  ; max = 17000
        BLE.S  .store_raw_speed                 ; $00944C
        MOVE.W  #$4268,D3                       ; $00944E
.store_raw_speed:
        MOVE.W  D3,$0074(A0)                    ; $009452  ; store raw speed
        RTS                                     ; $009456
