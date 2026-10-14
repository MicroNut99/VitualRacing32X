; ============================================================================
; collision_avoidance_speed_calc — AI Collision Avoidance + Speed Calculation
; ROM Range: $00A470-$00A664 (502 bytes)
; ============================================================================
; AI/physics function that computes entity speed and performs proximity-based
; collision avoidance. Reads entity fields for speed, position, heading, and
; applies graduated steering/braking responses based on distance thresholds.
;
; Structure:
;   $A470-$A4AC: Speed calculation from entity field $24 + table lookup
;   $A4AE-$A4B6: Proximity gate (bit 1 of $55(A0))
;   $A4B8-$A4E8: Target entity lookup via $A4(A0) index
;   $A4EC-$A514: Manhattan distance computation (|dX|+|dY|, dZ)
;   $A514-$A580: Avoidance steering with threshold-based response
;   $A582-$A664: Secondary entity path with different thresholds
;
; Falls through to physics_integration at $A666 (no RTS in this block).
; Alternate no-target path at $A6F8 branches back to $A666.
;
; Entry: A0 = entity pointer, A1 = target entity pointer (from caller)
; Uses: D0-D3, D6-D7, A0-A3
; Called from: counter_guard ($006FFA) via BNE.W
; ============================================================================

collision_avoidance_speed_calc:
        movea.l $0018(a0),a3            ; $00A470  load entity data pointer
        move.w  $0024(a0),d0            ; $00A474  load speed table index
        move.w  d0,d1                   ; $00A478  D1 = index
        add.w   d0,d0                   ; $00A47A  D0 = index * 2
        add.w   d0,d1                   ; $00A47C  D1 = index * 3
        add.w   d1,d1                   ; $00A47E  D1 = index * 6
        move.l  (12,a3,d1.w),($FFFFA000).w  ; $00A480  store table entry to RAM
        move.w  #$0096,d0               ; $00A486  default speed = 150
        tst.w   $006A(a0)              ; $00A48A  check override flag
        bne.s   .label_A4AA            ; $00A48E  if set, skip table lookup
        move.w  $000A(a0),d0            ; $00A490  load base speed
        movea.l ($FFFFC280).w,a1        ; $00A494  load speed table pointer
        move.w  $00C2(a0),d2            ; $00A498  load speed modifier
        asr.w   #3,d2                   ; $00A49C  divide modifier by 8
        move.w  (a1,d2.w),d2            ; $00A49E  look up modifier in table
        muls.w  (4,a3,d1.w),d2         ; $00A4A2  multiply by entity factor
        asr.l   #8,d2                   ; $00A4A6  scale result down
        add.w   d2,d0                   ; $00A4A8  add modifier to speed
.label_A4AA:
        move.w  d0,$0008(a0)            ; $00A4AA  store final speed
; --- proximity gate ---
        btst    #1,$0055(a0)            ; $00A4AE  check avoidance-enabled bit
        beq.w   physics_integration     ; $00A4B4  if clear, skip to physics
; --- target entity lookup ---
        move.w  $00A4(a0),d0            ; $00A4B8  load target entity index
        beq.w   collision_avoidance_no_target  ; $00A4BC  if zero, no-target path
        lea     ($FFFF9000).w,a1        ; $00A4C0  entity table base
        asl.w   #8,d0                   ; $00A4C4  index * 256 = byte offset
        lea     (a1,d0.w),a1            ; $00A4C6  A1 = target entity
        tst.w   $00A4(a1)              ; $00A4CA  check target's own target
        beq.w   collision_avoidance_no_target  ; $00A4CE  if zero, no-target path
        lea     ($FFFF9000).w,a1        ; $00A4D2  reload entity table base
        move.w  $00A6(a0),d0            ; $00A4D6  load secondary index
        beq.s   .label_A4E6            ; $00A4DA  if zero, skip validation
        cmpi.w  #$0082,$0004(a0)        ; $00A4DC  check entity speed class
        blt.w   physics_integration     ; $00A4E2  if below threshold, skip
.label_A4E6:
        asl.w   #8,d0                   ; $00A4E6  index * 256 = byte offset
        lea     (a1,d0.w),a1            ; $00A4E8  A1 = secondary entity
; --- distance computation ---
        move.w  $0030(a1),d0            ; $00A4EC  target X position
        sub.w   $0030(a0),d0            ; $00A4F0  dX = target.X - self.X
        bpl.s   .label_A4F8            ; $00A4F4  if positive, skip negate
        neg.w   d0                      ; $00A4F6  D0 = |dX|
.label_A4F8:
        move.w  $0034(a1),d7            ; $00A4F8  target Y position
        sub.w   $0034(a0),d7            ; $00A4FC  dY = target.Y - self.Y
        bpl.s   .label_A504            ; $00A500  if positive, skip negate
        neg.w   d7                      ; $00A502  D7 = |dY|
.label_A504:
        add.w   d0,d7                   ; $00A504  D7 = |dX| + |dY| (Manhattan)
        move.w  $0072(a1),d3            ; $00A506  target Z position
        sub.w   $0072(a0),d3            ; $00A50A  dZ = target.Z - self.Z
        move.w  d3,d6                   ; $00A50E  D6 = signed dZ
        bpl.s   .label_A514            ; $00A510  if positive, skip negate
        neg.w   d6                      ; $00A512  D6 = |dZ|
; --- avoidance steering (threshold-based) ---
.label_A514:
        cmpi.w  #$0140,d7              ; $00A514  compare Manhattan dist to 320
        bge.w   .label_A582            ; $00A518  if >= 320, try secondary path
        cmpi.w  #$00A0,d7              ; $00A51C  compare to 160
        ble.s   .label_A52E            ; $00A520  if <= 160, close range
        move.w  $0004(a0),d0            ; $00A522  self speed class
        sub.w   $0004(a1),d0            ; $00A526  compare with target
        bgt.w   .label_A55C            ; $00A52A  if faster, skip to speed check
.label_A52E:
        cmpi.w  #$0040,d6              ; $00A52E  compare |dZ| to 64
        bge.s   .label_A55C            ; $00A532  if >= 64, skip steering
        moveq   #$40,d0                ; $00A534  D0 = 64
        sub.w   d6,d0                   ; $00A536  D0 = 64 - |dZ| (proximity factor)
        tst.w   d3                      ; $00A538  check signed dZ
        bpl.s   .label_A53E            ; $00A53A  if positive, keep sign
        neg.w   d0                      ; $00A53C  flip steering direction
.label_A53E:
        cmpi.w  #$001C,($FFFFC07A).w   ; $00A53E  check game mode flag
        beq.s   .label_A550            ; $00A544  if == $1C, use alternate scale
        add.w   d0,d0                   ; $00A546  D0 *= 2
        move.w  d0,d1                   ; $00A548  D1 = D0
        add.w   d0,d0                   ; $00A54A  D0 *= 2 (total *4)
        add.w   d1,d0                   ; $00A54C  D0 += D1 (total *6)
        bra.s   .label_A558            ; $00A54E  apply steering
.label_A550:
        asl.w   #2,d0                   ; $00A550  D0 *= 4
        move.w  d0,d1                   ; $00A552  D1 = D0
        asl.w   #3,d1                   ; $00A554  D1 *= 8 (original * 32)
        add.w   d1,d0                   ; $00A556  D0 += D1 (total *36)
.label_A558:
        add.w   d0,$0040(a0)            ; $00A558  apply steering adjustment
; --- speed avoidance ---
.label_A55C:
        cmpi.w  #$0070,d7              ; $00A55C  compare Manhattan dist to 112
        bge.s   .label_A582            ; $00A560  if >= 112, try secondary path
        move.w  $0040(a1),d0            ; $00A562  target heading
        sub.w   $0040(a0),d0            ; $00A566  heading delta
        move.w  d0,d1                   ; $00A56A  D1 = heading delta
        tst.w   d3                      ; $00A56C  check signed dZ
        blt.s   .label_A572            ; $00A56E  if negative, skip negate
        neg.w   d1                      ; $00A570  flip direction
.label_A572:
        tst.w   d1                      ; $00A572  check adjusted delta
        blt.s   .label_A582            ; $00A574  if negative, skip
        cmpi.w  #$1800,d1              ; $00A576  compare to threshold
        bge.s   .label_A582            ; $00A57A  if >= $1800, skip
        asr.w   #1,d0                   ; $00A57C  halve heading delta
        add.w   d0,$0040(a0)            ; $00A57E  apply heading correction
; --- secondary entity path ---
.label_A582:
        lea     ($FFFF9000).w,a2        ; $00A582  entity table base
        move.w  $00A4(a0),d0            ; $00A586  load target entity index
        lsl.w   #8,d0                   ; $00A58A  index * 256
        lea     (a2,d0.w),a1            ; $00A58C  A1 = primary target
        move.w  $00A4(a1),d0            ; $00A590  load target's own target
        bne.s   .label_A5AC            ; $00A594  if nonzero, use it
        lsl.w   #8,d0                   ; $00A596  index * 256 (D0=0, no-op)
        lea     (a2,d0.w),a2            ; $00A598  A2 = secondary target
        move.w  $0024(a2),d0            ; $00A59C  secondary speed index
        sub.w   $0024(a1),d0            ; $00A5A0  compare speeds
        cmpi.w  #$0004,d0              ; $00A5A4  threshold check
        bgt.s   .label_A5AC            ; $00A5A8  if much faster, keep A1
        lea     (a2),a1                 ; $00A5AA  A1 = closer/slower entity
.label_A5AC:
        move.w  $0030(a1),d0            ; $00A5AC  target X position
        sub.w   $0030(a0),d0            ; $00A5B0  dX
        bpl.s   .label_A5B8            ; $00A5B4  if positive, skip negate
        neg.w   d0                      ; $00A5B6  D0 = |dX|
.label_A5B8:
        move.w  $0034(a1),d7            ; $00A5B8  target Y position
        sub.w   $0034(a0),d7            ; $00A5BC  dY
        bpl.s   .label_A5C4            ; $00A5C0  if positive, skip negate
        neg.w   d7                      ; $00A5C2  D7 = |dY|
.label_A5C4:
        add.w   d0,d7                   ; $00A5C4  D7 = Manhattan distance
        move.w  $0072(a1),d3            ; $00A5C6  target Z position
        sub.w   $0072(a0),d3            ; $00A5CA  dZ
        move.w  d3,d6                   ; $00A5CE  D6 = signed dZ
        bpl.s   .label_A5D4            ; $00A5D0  if positive, skip negate
        neg.w   d6                      ; $00A5D2  D6 = |dZ|
.label_A5D4:
        move.w  $0006(a1),d0            ; $00A5D4  target track position
        sub.w   $0006(a0),d0            ; $00A5D8  position delta
        bge.s   .label_A606            ; $00A5DC  if ahead or equal, skip
        cmpi.w  #$01E0,d7              ; $00A5DE  compare Manhattan dist to 480
        bgt.s   .label_A606            ; $00A5E2  if > 480, too far
        cmpi.w  #$0040,d7              ; $00A5E4  compare to 64
        ble.s   .label_A606            ; $00A5E8  if <= 64, too close for steering
        cmpi.w  #$0030,d6              ; $00A5EA  compare |dZ| to 48
        bgt.s   .label_A606            ; $00A5EE  if > 48, skip
        cmpi.w  #$0064,$0004(a0)        ; $00A5F0  check entity speed class
        ble.s   .label_A606            ; $00A5F6  if <= 100, skip
        move.w  #$01E0,d1              ; $00A5F8  D1 = 480
        sub.w   d7,d1                   ; $00A5FC  D1 = 480 - Manhattan dist
        asr.w   #6,d1                   ; $00A5FE  D1 /= 64 (proximity scale)
        asl.w   d1,d0                   ; $00A600  scale position delta by proximity
        add.w   d0,$0008(a0)            ; $00A602  apply speed adjustment
.label_A606:
        cmpi.w  #$0070,d6              ; $00A606  compare |dZ| to 112
        bge.w   .label_A640            ; $00A60A  if >= 112, skip to heading check
        tst.w   d0                      ; $00A60E  check position delta
        ble.s   .label_A618            ; $00A610  if <= 0, behind target
        cmpi.w  #$00A0,d7              ; $00A612  compare Manhattan dist to 160
        bgt.s   .label_A640            ; $00A616  if > 160, skip
.label_A618:
        neg.w   d0                      ; $00A618  flip sign
        asr.w   #1,d0                   ; $00A61A  halve value
        addi.w  #$0A00,d0              ; $00A61C  add bias ($0A00 = 2560)
        move.w  d7,d1                   ; $00A620  D1 = Manhattan dist
        asl.w   #4,d1                   ; $00A622  D1 *= 16
        cmp.w   d1,d0                   ; $00A624  compare biased value to scaled dist
        bgt.s   .label_A640            ; $00A626  if biased > scaled, skip
        cmpi.w  #$0040,d6              ; $00A628  compare |dZ| to 64
        bge.s   .label_A640            ; $00A62C  if >= 64, skip steering
        moveq   #$40,d0                ; $00A62E  D0 = 64
        sub.w   d6,d0                   ; $00A630  D0 = 64 - |dZ| (proximity factor)
        tst.w   d3                      ; $00A632  check signed dZ
        bpl.s   .label_A638            ; $00A634  if positive, keep sign
        neg.w   d0                      ; $00A636  flip steering direction
.label_A638:
        add.w   d0,d0                   ; $00A638  D0 *= 2
        add.w   d0,d0                   ; $00A63A  D0 *= 2 (total *4)
        add.w   d0,$0040(a0)            ; $00A63C  apply steering adjustment
; --- heading-based speed avoidance (secondary) ---
.label_A640:
        cmpi.w  #$0070,d7              ; $00A640  compare Manhattan dist to 112
        bge.s   physics_integration     ; $00A644  if >= 112, done — fall through
        move.w  $0040(a1),d0            ; $00A646  target heading
        sub.w   $0040(a0),d0            ; $00A64A  heading delta
        move.w  d0,d1                   ; $00A64E  D1 = heading delta
        tst.w   d3                      ; $00A650  check signed dZ
        blt.s   .label_A656            ; $00A652  if negative, skip negate
        neg.w   d1                      ; $00A654  flip direction
.label_A656:
        tst.w   d1                      ; $00A656  check adjusted delta
        ble.s   physics_integration     ; $00A658  if <= 0, done — fall through
        cmpi.w  #$1800,d1              ; $00A65A  compare to threshold
        bge.s   physics_integration     ; $00A65E  if >= $1800, done — fall through
        asr.w   #1,d0                   ; $00A660  halve heading delta
        add.w   d0,$0040(a0)            ; $00A662  apply heading correction
