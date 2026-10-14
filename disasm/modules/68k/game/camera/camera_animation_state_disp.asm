; ============================================================================
; camera_animation_state_disp — Camera Animation State Dispatcher
; ROM Range: $00B7EE-$00B964 (374 bytes)
; State machine for camera animation transitions. Reads state byte
; from $C045, dispatches via jump table at $00B864. Oscillates a
; counter between 0-$10 for smooth animation interpolation. Computes
; display viewport coordinates from animation data tables and writes
; to screen position registers. Second phase loads camera parameters
; from ROM and populates display object (A2) fields.
;
; Entry: A0 = player entity, A2 = display object
; Uses: D0, D1, D2, D4, A0, A1, A2, A4
; Confidence: high
; ============================================================================

; --- State dispatch: read anim state byte, jump via table ---
camera_animation_state_disp:
        MOVEQ   #$00,D0                         ; $00B7EE
        MOVE.B  (-16283).W,D0                   ; $00B7F0 ; anim state index
        MOVEA.L $00B864(PC,D0.W),A1             ; $00B7F4 ; handler from table
        JMP     (A1)                            ; $00B7F8 ; dispatch
; --- Entry point A: simple passthrough (no oscillation) ---
        MOVEQ   #$00,D2                         ; $00B7FA
        MOVE.B  (-15614).W,D2                   ; $00B7FC ; phase counter
        BRA.S  .update_state                        ; $00B800
; --- Entry point B: oscillating phase counter (0↔$10) ---
        MOVEQ   #$00,D0                         ; $00B802
        MOVE.B  (-15614).W,D0                   ; $00B804 ; current phase
        MOVE.W  D0,D2                           ; $00B808 ; save for blend
        TST.B  (-15599).W                       ; $00B80A ; direction flag
        BEQ.S  .increment_phase                        ; $00B80E ; 0=incrementing
; decrementing phase
        SUBQ.W  #4,D0                           ; $00B810 ; phase -= 4
        SUBQ.W  #1,(-16312).W                   ; $00B812 ; keyframe timer--
        TST.W  D0                               ; $00B816
        BGE.S  .update_state                        ; $00B818 ; still positive
; hit bottom, reverse direction
        MOVE.B  #$00,(-15599).W                 ; $00B81A ; dir = increment
        MOVE.W  #$0001,(-16312).W               ; $00B820 ; reset timer
        MOVEQ   #$04,D0                         ; $00B826 ; start at 4
        BRA.S  .update_state                        ; $00B828
; incrementing phase
.increment_phase:
        ADDQ.W  #4,D0                           ; $00B82A ; phase += 4
        ADDQ.W  #1,(-16312).W                   ; $00B82C ; keyframe timer++
        CMPI.W  #$0010,D0                       ; $00B830 ; reached max ($10)?
        BLT.S  .update_state                        ; $00B834
; hit top, reverse direction
        MOVE.B  #$01,(-15599).W                 ; $00B836 ; dir = decrement
        MOVE.W  #$0002,(-16312).W               ; $00B83C ; reset timer
        MOVEQ   #$08,D0                         ; $00B842 ; clamp at 8
; --- Compute 2D table index from phase+counter ---
.update_state:
        MOVE.B  D0,(-15614).W                   ; $00B844 ; store phase
        ADD.W   D2,D2                           ; $00B848 ; prev_phase * 2
        ADD.W   D2,D2                           ; $00B84A ; prev_phase * 4
        ADD.W   D2,D0                           ; $00B84C ; idx = phase + prev*4
        MOVE.B  #$01,(-16284).W                 ; $00B84E ; mark anim active
        MOVE.B  D0,(-16283).W                   ; $00B854 ; store new state
        MOVE.B  #$14,(-15613).W                 ; $00B858 ; frame count = 20
        MOVEA.L $00B864(PC,D0.W),A1             ; $00B85E ; dispatch handler
        JMP     (A1)                            ; $00B862
; jump table: 16 longword entries for state×phase grid
        DC.W    $0088                           ; $00B864
        CMP.L  -(A4),D4                         ; $00B866
        DC.W    $0088                           ; $00B868
        EOR.W  D4,-(A4)                         ; $00B86A
        DC.W    $0088                           ; $00B86C
        EOR.W  D4,-(A4)                         ; $00B86E
        DC.W    $0088                           ; $00B870
        DC.W    $B97A                           ; $00B872
        DC.W    $0088                           ; $00B874
        CMP.L  -(A4),D4                         ; $00B876
        DC.W    $0088                           ; $00B878
        CMP.L  -(A4),D4                         ; $00B87A
        DC.W    $0088                           ; $00B87C
        EOR.W  D4,-(A4)                         ; $00B87E
        DC.W    $0088                           ; $00B880
        DC.W    $B97A                           ; $00B882
        DC.W    $0088                           ; $00B884
        CMP.L  -(A4),D4                         ; $00B886
        DC.W    $0088                           ; $00B888
        EOR.W  D4,-(A4)                         ; $00B88A
        DC.W    $0088                           ; $00B88C
        CMP.L  -(A4),D4                         ; $00B88E
        DC.W    $0088                           ; $00B890
        DC.W    $B97A                           ; $00B892
        DC.W    $0088                           ; $00B894
        CMP.L  -(A4),D4                         ; $00B896
        DC.W    $0088                           ; $00B898
        EOR.W  D4,-(A4)                         ; $00B89A
        DC.W    $0088                           ; $00B89C
        EOR.W  D4,-(A4)                         ; $00B89E
        DC.W    $0088                           ; $00B8A0
        CMP.L  -(A4),D4                         ; $00B8A2
; --- Keyframe interpolation: read viewport coords from anim data ---
        MOVEA.L (-14524).W,A1                   ; $00B8A4 ; anim data base ptr
        ADD.W  (-14148).W,D0                    ; $00B8A8 ; + camera offset
        MOVEA.L $00(A1,D0.W),A1                 ; $00B8AC ; keyframe array ptr
        MOVEQ   #$00,D0                         ; $00B8B0
        MOVE.B  (-15613).W,D0                   ; $00B8B2 ; frame countdown
        ADD.W   D0,D0                           ; $00B8B6 ; *4 for longword
        ADD.W   D0,D0                           ; $00B8B8
        MOVE.L  $00(A1,D0.W),D0                 ; $00B8BA ; packed X:Y coords
        MOVE.W  D0,(-16298).W                   ; $00B8BE ; low word = Y pos
        SWAP    D0                              ; $00B8C2
        MOVE.W  D0,(-16300).W                   ; $00B8C4 ; high word = X pos
        MOVE.B  #$00,(-15588).W                 ; $00B8C8 ; clear interp flag
        SUBQ.B  #1,(-15613).W                   ; $00B8CE ; frame count--
        BNE.W  .done                        ; $00B8D2 ; not last frame
; --- Animation complete: populate display object ---
        MOVE.B  #$00,(-16284).W                 ; $00B8D6 ; clear anim active
        MOVE.L  (-14512).W,$0010(A2)            ; $00B8DC ; set primary pos
        TST.W  $008A(A0)                        ; $00B8E2 ; entity param?
        BNE.S  .after_position_set                        ; $00B8E6
        MOVE.L  (-14556).W,$0010(A2)            ; $00B8E8 ; use alt position
.after_position_set:
        MOVEQ   #$00,D2                         ; $00B8EE ; secondary count=0
        MOVE.L  (-14552).W,D1                   ; $00B8F0 ; secondary data
        BEQ.S  .after_secondary_set                        ; $00B8F4 ; none
        MOVE.L  D1,$0024(A2)                    ; $00B8F6 ; set secondary pos
        MOVE.L  (-14548).W,$0038(A2)            ; $00B8FA ; set secondary ext
        MOVEQ   #$01,D2                         ; $00B900 ; secondary active
.after_secondary_set:
        MOVE.W  D2,$0014(A2)                    ; $00B902 ; primary count
        MOVE.W  D2,$0028(A2)                    ; $00B906 ; secondary count
        MOVE.W  #$0001,(-16308).W               ; $00B90A ; display update flag
        MOVE.W  #$0002,$0000(A2)                ; $00B910 ; obj state = active
; --- Load camera parameters from ROM table ---
        MOVEA.L (-14536).W,A1                   ; $00B916 ; cam param table
        MOVE.W  (A1)+,$0016(A2)                 ; $00B91A ; param 0 (FOV/angle)
        MOVE.W  (A1)+,$0018(A2)                 ; $00B91E ; param 1
        MOVE.W  (A1)+,$001A(A2)                 ; $00B922 ; param 2
        MOVE.W  (A1)+,$002A(A2)                 ; $00B926 ; param 3
        MOVE.W  (A1)+,$002C(A2)                 ; $00B92A ; param 4
        MOVE.W  (A1),$002E(A2)                  ; $00B92E ; param 5
        MOVE.W  #$0000,$003C(A2)                ; $00B932 ; clear rotation
        MOVE.W  #$0000,$0050(A2)                ; $00B938 ; clear ext flag
; --- Optional: load extra camera data ---
        MOVEA.L (-14528).W,A1                   ; $00B93E ; extra data ptr
        CMPA.L  #$00000000,A1                   ; $00B942 ; NULL check
        BEQ.S  .done                        ; $00B948
        MOVE.W  (A1)+,$0052(A2)                 ; $00B94A ; extra param 0
        MOVE.W  (A1)+,$0054(A2)                 ; $00B94E ; extra param 1
        MOVE.W  (A1),$0056(A2)                  ; $00B952 ; extra param 2
        MOVE.W  #$0001,$0050(A2)                ; $00B956 ; mark extra active
        MOVE.L  (-14544).W,$0060(A2)            ; $00B95C ; extra position
.done:
        RTS                                     ; $00B962
