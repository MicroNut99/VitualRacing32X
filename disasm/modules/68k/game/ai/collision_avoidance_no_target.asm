; ============================================================================
; collision_avoidance_no_target — AI Collision Avoidance (No-Target Path)
; ROM Range: $00A6F8-$00A79E (168 bytes)
; ============================================================================
; Alternate path of collision_avoidance_speed_calc when entity has no target
; ($A4(A0) == 0 or target invalid). Computes Manhattan distance to nearest
; entity, applies braking and lateral steering if within thresholds.
;
; Reached via BEQ.W from collision_avoidance_speed_calc at $A4BC/$A4CE.
; Ends with BRA.W $A666 (back to physics_integration).
;
; Entry: A0 = entity pointer (from collision_avoidance_speed_calc)
; Uses: D0-D3, D6-D7, A1
; ============================================================================

collision_avoidance_no_target:
        lea     ($FFFF9000).w,a1                ; $00A6F8  load entity list base
        move.w  $0030(a1),d0                    ; $00A6FC  nearest entity X pos
        sub.w   $0030(a0),d0                    ; $00A700  delta X = nearest.X - self.X
        bpl.s   .abs_dx                         ; $00A704  if positive, skip negate
        neg.w   d0                              ; $00A706  |delta X|
.abs_dx:
        move.w  $0034(a1),d7                    ; $00A708  nearest entity Z pos
        sub.w   $0034(a0),d7                    ; $00A70C  delta Z = nearest.Z - self.Z
        bpl.s   .abs_dz                         ; $00A710  if positive, skip negate
        neg.w   d7                              ; $00A712  |delta Z|
.abs_dz:
        add.w   d0,d7                           ; $00A714  D7 = Manhattan distance (|dX|+|dZ|)
        move.w  $0072(a1),d3                    ; $00A716  nearest entity lateral offset
        sub.w   $0072(a0),d3                    ; $00A71A  signed lateral delta
        move.w  d3,d6                           ; $00A71E  D6 = copy for abs
        bpl.s   .threshold_checks               ; $00A720  if positive, skip negate
        neg.w   d6                              ; $00A722  D6 = |lateral delta|
; --- threshold checks: skip to physics_integration if far away ---
.threshold_checks:
        move.w  $0006(a1),d0                    ; $00A724  nearest entity track segment
        sub.w   $0006(a0),d0                    ; $00A728  segment difference
        bge.w   physics_integration             ; $00A72C  if ahead of us, skip
        cmpi.w  #$0230,d7                       ; $00A730  Manhattan distance threshold
        bgt.w   physics_integration             ; $00A734  too far away, skip
        cmpi.w  #$0040,d6                       ; $00A738  lateral distance threshold
        bgt.w   physics_integration             ; $00A73C  too far laterally, skip
; --- braking when close ---
        cmpi.w  #$0064,$0004(a0)                ; $00A740  check current speed
        ble.s   .exit_to_physics                ; $00A746  if speed <= 100, skip braking
        move.w  #$0230,d1                       ; $00A748  max Manhattan distance
        sub.w   d7,d1                           ; $00A74C  D1 = proximity factor (closer = larger)
        asr.w   #6,d1                           ; $00A74E  D1 >>= 6 (scale down)
        asl.w   d1,d0                           ; $00A750  D0 <<= D1 (variable shift by proximity)
        add.w   d0,$0008(a0)                    ; $00A752  add braking to acceleration
        bpl.s   .lateral_steering               ; $00A756  if still positive, continue
        clr.w   $0008(a0)                       ; $00A758  clamp acceleration to zero
; --- lateral steering ---
.lateral_steering:
        cmpi.w  #$0070,d6                       ; $00A75C  lateral threshold for steering
        bge.w   .exit_to_physics                ; $00A760  too far laterally, skip steering
        tst.w   d0                              ; $00A764  test braking value
        ble.s   .negate_and_shift               ; $00A766  if <= 0, go to negate path
        cmpi.w  #$00F0,d7                       ; $00A768  close-range Manhattan threshold
        bgt.s   .exit_to_physics                ; $00A76C  if far, skip steering
.negate_and_shift:
        neg.w   d0                              ; $00A76E  negate D0
        asr.w   #1,d0                           ; $00A770  D0 /= 2
        addi.w  #$0F00,d0                       ; $00A772  add steering base offset
        move.w  d7,d1                           ; $00A776  D1 = Manhattan distance
        asl.w   #4,d1                           ; $00A778  D1 *= 16
        cmp.w   d1,d0                           ; $00A77A  compare scaled distance vs steering
        bgt.s   .exit_to_physics                ; $00A77C  if steering > scaled dist, skip
        cmpi.w  #$0060,d6                       ; $00A77E  tighter lateral threshold
        bge.w   .exit_to_physics                ; $00A782  if too far laterally, skip
        moveq   #$60,d0                         ; $00A786  max lateral steer magnitude
        sub.w   d6,d0                           ; $00A788  D0 = steer strength (closer = stronger)
        tst.w   d3                              ; $00A78A  test signed lateral delta
        bpl.s   .apply_lateral                  ; $00A78C  if positive, keep sign
        neg.w   d0                              ; $00A78E  negate for opposite direction
.apply_lateral:
        asl.w   #3,d0                           ; $00A790  D0 *= 8
        move.w  d0,d1                           ; $00A792  D1 = D0
        add.w   d1,d1                           ; $00A794  D1 *= 2
        add.w   d1,d0                           ; $00A796  D0 = D0 + 2*D0 = 3*D0 (total: 24x)
        add.w   d0,$0040(a0)                    ; $00A798  apply lateral steering force
; --- return to physics_integration ---
.exit_to_physics:
        bra.w   physics_integration             ; $00A79C  jump back to main physics loop
