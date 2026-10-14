; ============================================================================
; ai_entity_main_update_orch — AI Entity Main Update Orchestrator
; ROM Range: $00A972-$00AC3E (716 bytes)
; Main per-frame update for AI entities. Handles spawn positioning with
; distance-based approach ramp, heading calculation via ai_steering_calc,
; speed convergence toward target, movement integration via position_update.
; Multiple entry points for different AI states: initial spawn, approach,
; active racing, and finish/retirement. Manages race table slots and
; mode flags.
;
; Entry: A0 = AI entity pointer
; Uses: D0, D1, D2, D3, D4, D5, A0, A1
; Calls: $003C7E (player_table_setup), $006FDE (position_update),
;        $009B12 (movement_calc), $00A1FC (race_state_read),
;        $00A7A0 (ai_steering_calc), $00ACC0 (race_mode_flag_set)
; Object fields: +$02 flags, +$04 speed, +$06 display speed, +$14 timer,
;   +$30 x_pos, +$34 y_pos, +$3C heading, +$40 target heading,
;   +$46 turn rate, +$7A gear, +$8E steer vel, +$90 drift,
;   +$AE slot index, +$B0 spawn timer, +$B8 trail, +$BC decel
; Confidence: high
; ============================================================================

; --- Main entry: set race flags and per-frame init ---
ai_entity_main_update_orch:
        jsr     race_mode_flag_set(pc)  ; $4EBA $034C
        TST.W  (-16306).W                       ; $00A976 ; countdown active?
        BNE.S  .after_countdown                        ; $00A97A
        SUBQ.W  #1,(-16306).W                   ; $00A97C ; tick countdown
.after_countdown:
        CLR.W  (-16346).W                       ; $00A980 ; clear vis counter
        CLR.B  (-15610).W                       ; $00A984 ; clear AI flag
        jsr     sprite_hud_layout_builder+84(pc); $4EBA $92F4
; --- Look up spawn target position from slot tables ---
        DC.W    $43FA,$FF3A         ; LEA     $00A8C8(PC),A1; $00A98C ; X offset table
        MOVE.W  (-14178).W,D0                   ; $00A990 ; difficulty index
        MOVE.W  $00(A1,D0.W),D5                 ; $00A994 ; X offset for dist
        DC.W    $43FA,$FECE         ; LEA     $00A868(PC),A1; $00A998 ; spawn pos table
        MOVE.W  (-14176).W,D1                   ; $00A99C ; camera mode
        ADD.W   D1,D1                           ; $00A9A0 ; *4 (longword stride)
        ADD.W   D1,D1                           ; $00A9A2
        MOVE.W  $00AE(A0),D0                    ; $00A9A4 ; slot index
        ADD.W   D0,D0                           ; $00A9A8 ; *4
        ADD.W   D0,D0                           ; $00A9AA
        ADD.W   D1,D0                           ; $00A9AC ; combined index
        MOVE.W  $00(A1,D0.W),D1                 ; $00A9AE ; target X
        MOVE.W  $02(A1,D0.W),D2                 ; $00A9B2 ; target Y
; --- Distance check: if close enough, snap to spawn ---
        MOVE.W  D2,D4                           ; $00A9B6
        SUB.W  $0034(A0),D4                     ; $00A9B8 ; dist = target_Y - y
        CMPI.W  #$0002,D4                       ; $00A9BC ; within 2 units?
        BGE.S  .dist_check_close                        ; $00A9C0 ; no, approach
; --- Snap to spawn: zero all motion fields ---
        MOVE.W  D1,$0030(A0)                    ; $00A9C2 ; set x_pos
        MOVE.W  D2,$0034(A0)                    ; $00A9C6 ; set y_pos
        MOVEQ   #$00,D0                         ; $00A9CA
        MOVE.W  D0,$003C(A0)                    ; $00A9CC ; heading = 0
        MOVE.W  D0,$0040(A0)                    ; $00A9D0 ; target heading = 0
        MOVE.W  D0,$008E(A0)                    ; $00A9D4 ; steer_vel = 0
        MOVE.W  D0,$0090(A0)                    ; $00A9D8 ; drift = 0
        MOVE.W  D0,$0006(A0)                    ; $00A9DC ; display_speed = 0
        MOVE.W  D0,$0004(A0)                    ; $00A9E0 ; speed = 0
        MOVE.W  D0,$007A(A0)                    ; $00A9E4 ; gear = 0
        MOVE.W  D0,$0092(A0)                    ; $00A9E8 ; slide = 0
        MOVE.W  D0,$0014(A0)                    ; $00A9EC ; timer = 0
        MOVE.W  D0,$008C(A0)                    ; $00A9F0 ; param = 0
        MOVE.W  D0,$00B8(A0)                    ; $00A9F4 ; trail = 0
        CLR.W  (-16340).W                       ; $00A9F8 ; clear race counter
; set slot state to "waiting"
        LEA     (-16292).W,A1                   ; $00A9FC ; race slot table
        MOVE.W  $00AE(A0),D0                    ; $00AA00 ; slot index
        ADD.W   D0,D0                           ; $00AA04 ; *2 for word
        MOVE.W  #$0002,$00(A1,D0.W)             ; $00AA06 ; state = 2 (ready)
        MOVE.W  #$0078,$00B0(A0)                ; $00AA0C ; spawn timer = 120
        CLR.W  (-16306).W                       ; $00AA12 ; clear countdown
        jmp     entity_force_integration_and_speed_calc+18(pc); $4EFA $E8FA
; --- Approach ramp: 4 distance bands with different speeds ---
; Band 1: very close (<$80), slow approach speed $20
.dist_check_close:
        CMPI.W  #$0080,D4                       ; $00AA1A ; dist < 128?
        BGT.S  .dist_check_medium                        ; $00AA1E
        MOVE.W  D1,(-24574).W                   ; $00AA20 ; nav target X
        MOVE.W  D2,(-24572).W                   ; $00AA24 ; nav target Y
        MOVE.W  #$0020,(-24570).W               ; $00AA28 ; speed = 32
        BRA.W  .compute_steering                        ; $00AA2E
; Band 2: medium ($80-$180), speed = dist*3/16 + 8
.dist_check_medium:
        CMPI.W  #$0180,D4                       ; $00AA32 ; dist < 384?
        BGT.S  .dist_check_far                        ; $00AA36
        MOVE.W  D1,(-24574).W                   ; $00AA38 ; nav target X
        MOVE.W  D2,(-24572).W                   ; $00AA3C ; nav target Y
        SUBI.W  #$0040,(-24572).W               ; $00AA40 ; offset Y by -64
        MOVE.W  D4,D0                           ; $00AA46 ; dist
        ASR.W  #4,D0                            ; $00AA48 ; /16
        MOVE.W  D0,D3                           ; $00AA4A ; save
        ADD.W   D0,D0                           ; $00AA4C ; *2
        ADD.W   D3,D0                           ; $00AA4E ; *3 total
        ADDQ.W  #8,D0                           ; $00AA50 ; +8
        MOVE.W  D0,(-24570).W                   ; $00AA52 ; target speed
        BRA.S  .compute_steering                        ; $00AA56
; Band 3: far ($180-$400), speed = dist/8 + $20, X offset
.dist_check_far:
        CMPI.W  #$0400,D4                       ; $00AA58 ; dist < 1024?
        BGT.S  .dist_very_far                        ; $00AA5C
        MOVE.W  D1,(-24574).W                   ; $00AA5E ; nav target X
        ADD.W  D5,(-24574).W                    ; $00AA62 ; + difficulty offset
        MOVE.W  D2,(-24572).W                   ; $00AA66 ; nav target Y
        SUBI.W  #$0080,(-24572).W               ; $00AA6A ; offset Y by -128
        MOVE.W  D4,D0                           ; $00AA70 ; dist
        ASR.W  #4,D0                            ; $00AA72 ; /16
        ADD.W   D0,D0                           ; $00AA74 ; *2 → /8 total
        ADDI.W  #$0020,D0                       ; $00AA76 ; +32
        MOVE.W  D0,(-24570).W                   ; $00AA7A ; target speed
        BRA.S  .compute_steering                        ; $00AA7E
; Band 4: very far (>$400), speed = dist/16 + $64, clamped
.dist_very_far:
        MOVE.W  D1,(-24574).W                   ; $00AA80 ; nav target X
        ADD.W  D5,(-24574).W                    ; $00AA84 ; + difficulty offset
        MOVE.W  D2,(-24572).W                   ; $00AA88 ; nav target Y
        SUBI.W  #$0080,(-24572).W               ; $00AA8C ; offset Y by -128
        MOVE.W  D4,D0                           ; $00AA92 ; dist
        ASR.W  #4,D0                            ; $00AA94 ; /16
        ADDI.W  #$0064,D0                       ; $00AA96 ; +100
        CMPI.W  #$00C8,D0                       ; $00AA9A ; max speed = 200
        BLE.S  .clamp_speed_max                        ; $00AA9E
        MOVE.W  #$00C8,D0                       ; $00AAA0
.clamp_speed_max:
        MOVE.W  D0,(-24570).W                   ; $00AAA4 ; target speed
; --- Steering: compute heading toward nav target ---
.compute_steering:
        MOVE.W  $0034(A0),D0                    ; $00AAA8 ; entity Y
        MOVE.W  $0030(A0),D1                    ; $00AAAC ; entity X
        NEG.W  D1                               ; $00AAB0 ; negate for atan2
        MOVE.W  (-24572).W,D2                   ; $00AAB2 ; nav Y
        MOVE.W  (-24574).W,D3                   ; $00AAB6 ; nav X
        NEG.W  D3                               ; $00AABA ; negate for atan2
        jsr     ai_steering_calc(pc)    ; $4EBA $FCE2 ; → D0 = target angle
        MOVE.W  D0,(-24568).W                   ; $00AAC0 ; save target heading
; clamp steering delta to +/-$140 per frame
        SUB.W  $003C(A0),D0                     ; $00AAC4 ; delta = target-heading
        CMPI.W  #$0140,D0                       ; $00AAC8 ; max turn rate
        BLE.S  .clamp_steer_max                        ; $00AACC
        MOVE.W  #$0140,D0                       ; $00AACE
.clamp_steer_max:
        CMPI.W  #$FEC0,D0                       ; $00AAD2 ; min turn rate (-$140)
        BGE.S  .clamp_steer_min                        ; $00AAD6
        MOVE.W  #$FEC0,D0                       ; $00AAD8
.clamp_steer_min:
        ADD.W  D0,$003C(A0)                     ; $00AADC ; heading += delta
; dead zone: zero heading if |heading| < $100
        MOVE.W  $003C(A0),D3                    ; $00AAE0
        BPL.S  .heading_abs                        ; $00AAE4
        NEG.W  D3                               ; $00AAE6
.heading_abs:
        CMPI.W  #$0100,D3                       ; $00AAE8 ; dead zone threshold
        BGE.S  .apply_steering                        ; $00AAEC
        CLR.W  $003C(A0)                        ; $00AAEE ; snap to zero
; --- Apply steering to entity fields ---
.apply_steering:
        MOVE.W  D0,$008E(A0)                    ; $00AAF2 ; steer_vel
        MOVE.W  D0,$0090(A0)                    ; $00AAF6 ; drift
        ADD.W   D0,D0                           ; $00AAFA ; *2
        NEG.W  D0                               ; $00AAFC ; invert for turn_rate
        MOVE.W  D0,$0046(A0)                    ; $00AAFE ; turn_rate
; smooth target heading convergence (1/4 per frame)
        MOVE.W  (-24568).W,D0                   ; $00AB02 ; target heading
        SUB.W  $0040(A0),D0                     ; $00AB06 ; - current target
        ASR.W  #2,D0                            ; $00AB0A ; /4
        ADD.W  D0,$0040(A0)                     ; $00AB0C ; converge
; --- Speed: convert distance-based speed to game units ---
; Formula: speed * 1000 * 256 / 3600 / 20
        MOVE.W  (-24570).W,D0                   ; $00AB10 ; raw target speed
        MULS    #$03E8,D0                       ; $00AB14 ; *1000
        LSL.L  #8,D0                            ; $00AB18 ; *256
        DIVS    #$0E10,D0                       ; $00AB1A ; /3600 (km/h→units)
        EXT.L   D0                              ; $00AB1E
        DIVS    #$0014,D0                       ; $00AB20 ; /20 (final scale)
        MOVE.W  D0,(-24570).W                   ; $00AB24 ; converted speed
; clamp acceleration to +$2F/-$50 per frame
        SUB.W  $0006(A0),D0                     ; $00AB28 ; delta from cur speed
        CMPI.W  #$002F,D0                       ; $00AB2C ; max accel = +47
        BLE.S  .clamp_accel_max                        ; $00AB30
        MOVE.W  #$002F,D0                       ; $00AB32
.clamp_accel_max:
        CMPI.W  #$FFB0,D0                       ; $00AB36 ; max decel = -80
        BGE.S  .clamp_accel_min                        ; $00AB3A
        MOVE.W  #$FFB0,D0                       ; $00AB3C
.clamp_accel_min:
        ADD.W  D0,$0006(A0)                     ; $00AB40 ; display_speed += accel
        jsr     entity_speed_clamp(pc)  ; $4EBA $EFCC
; --- Deceleration accumulator ---
        MOVE.W  $0004(A0),D0                    ; $00AB48 ; speed
        ASL.W  #5,D0                            ; $00AB4C ; *32
        CMPI.W  #$11F8,D0                       ; $00AB4E ; max = $11F8
        BLE.S  .clamp_shift_max                        ; $00AB52
        MOVE.W  #$11F8,D0                       ; $00AB54
.clamp_shift_max:
        CMPI.W  #$0000,D0                       ; $00AB58 ; min = 0
        BGE.S  .clamp_shift_min                        ; $00AB5C
        MOVE.W  #$0000,D0                       ; $00AB5E
.clamp_shift_min:
        SUB.W  D0,$00BC(A0)                     ; $00AB62 ; decel accum -= speed*32
; --- Position integration ---
        MOVE.W  $0040(A0),D0                    ; $00AB66 ; target heading
        NEG.W  D0                               ; $00AB6A ; movement direction
        MOVE.W  $0006(A0),D2                    ; $00AB6C ; display_speed
        MOVE.W  $0030(A0),D3                    ; $00AB70 ; x_pos
        MOVE.W  $0034(A0),D4                    ; $00AB74 ; y_pos
        jsr     entity_pos_update+70(pc); $4EBA $C464 ; integrate position
        MOVE.W  D3,$0030(A0)                    ; $00AB7C ; store new x_pos
        MOVE.W  D4,$0034(A0)                    ; $00AB80 ; store new y_pos
        jmp     entity_force_integration_and_speed_calc+18(pc); $4EFA $E78C
; === Spawn timer state: fade-in with visibility ramp ===
        jsr     race_mode_flag_set(pc)  ; $4EBA $0136
; compute visibility: (120 - timer) * $3BBB >> 16
        MOVEQ   #$78,D0                         ; $00AB8C ; max = 120
        SUB.W  $00B0(A0),D0                     ; $00AB8E ; - remaining timer
        MULU    #$3BBB,D0                       ; $00AB92 ; scale to [0..20]
        SWAP    D0                              ; $00AB96 ; >>16
        MOVE.W  D0,(-16346).W                   ; $00AB98 ; set visibility
; at visibility 20, trigger race_state_read
        CMPI.W  #$0014,(-16346).W               ; $00AB9C ; == 20?
        BNE.S  .spawn_timer_tick                        ; $00ABA2
        MOVE.W  #$0000,$008A(A0)                ; $00ABA4 ; clear entity param
        DC.W    $4EBA,$F650         ; JSR     $00A1FC(PC); $00ABAA ; race_state_read
.spawn_timer_tick:
        SUBQ.W  #1,$00B0(A0)                    ; $00ABAE ; spawn_timer--
        BNE.S  .return_state                        ; $00ABB2 ; not done
; timer expired: advance slot to state 3
        CLR.B  $00FF6970                        ; $00ABB4 ; clear spawn flag
        LEA     (-16292).W,A1                   ; $00ABBA ; race slot table
        MOVE.W  $00AE(A0),D0                    ; $00ABBE ; slot index
        ADD.W   D0,D0                           ; $00ABC2 ; *2
        MOVE.W  #$0003,$00(A1,D0.W)             ; $00ABC4 ; state = 3 (active)
.return_state:
        jmp     obj_state_return(pc)    ; $4EFA $FD2C
; === Finish state: scan slots for reorder, then retire ===
        LEA     (-16292).W,A1                   ; $00ABCE ; race slot table
        MOVEQ   #$00,D0                         ; $00ABD2
        MOVE.W  $00AE(A0),D1                    ; $00ABD4 ; our slot
        ADD.W   D1,D1                           ; $00ABD8 ; *2
; scan lower slots for state==1 (finished)
.scan_lower_slots:
        CMP.W  D1,D0                            ; $00ABDA
        BGE.S  .scan_upper_slots                        ; $00ABDC
        CMPI.W  #$0001,$00(A1,D1.W)             ; $00ABDE ; slot finished?
        DC.W    $6700,$FD12         ; BEQ.W  $00A8F8; $00ABE4 ; → reorder handler
        ADDQ.W  #2,D0                           ; $00ABE8
        BRA.S  .scan_lower_slots                        ; $00ABEA
; scan upper slots for state==4 (retiring)
.scan_upper_slots:
        MOVE.W  $00AE(A0),D0                    ; $00ABEC ; our slot
        ADDQ.W  #1,D0                           ; $00ABF0 ; start above us
        ADD.W   D0,D0                           ; $00ABF2 ; *2
.scan_upper_loop:
        CMPI.W  #$0008,D0                       ; $00ABF4 ; 4 slots max (*2)
        BGE.S  .retire_entity                        ; $00ABF8 ; none found
        CMPI.W  #$0004,$00(A1,D0.W)             ; $00ABFA ; slot retiring?
        DC.W    $6700,$FCF6         ; BEQ.W  $00A8F8; $00AC00 ; → reorder handler
        ADDQ.W  #2,D0                           ; $00AC04
        BRA.S  .scan_upper_loop                        ; $00AC06
; --- Entity retirement: mark inactive + cleanup ---
.retire_entity:
        ORI.W  #$4000,$0002(A0)                 ; $00AC08 ; set inactive flag
        MOVE.W  #$0050,(-16306).W               ; $00AC0E ; respawn delay = 80
        LEA     (-16292).W,A1                   ; $00AC14 ; race slot table
        MOVE.W  $00AE(A0),D0                    ; $00AC18 ; slot index
        ADD.W   D0,D0                           ; $00AC1C ; *2
        MOVE.W  #$0000,$00(A1,D0.W)             ; $00AC1E ; slot = 0 (empty)
        MOVE.W  #$003C,(-14162).W               ; $00AC24 ; scene timer = 60
        MOVE.W  (-16244).W,(-16262).W           ; $00AC2A ; copy position data
        BCLR    #1,(-15602).W                   ; $00AC30 ; clear race flag
        MOVE.B  #$91,(-14171).W                 ; $00AC36 ; SFX: retirement
        RTS                                     ; $00AC3C
