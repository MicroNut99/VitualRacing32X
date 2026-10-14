; ============================================================================
; camera_state_disp_viewport_control — Camera State Dispatcher + Viewport Control
; ROM Range: $00896E-$008B28 (442 bytes)
; Multi-state camera controller with acceleration/deceleration phases,
; button/flag checks, and a jump table dispatcher. Manages viewport
; scrolling, camera position updates, music trigger proximity checks,
; and render parameter writes. Jump table at $008A0E selects camera mode.
;
; Entry: A0 = camera/entity pointer
; Uses: D0, D1, D2, D3, D4, D5, D6, D7
; Object fields: +$04 speed, +$06 current speed, +$0E param,
;   +$1C height, +$24 segment, +$30 x_pos, +$34 y_pos
; Confidence: high
; ============================================================================

; --- Acceleration phase: double rate each frame, clamp $400 ---
camera_state_disp_viewport_control:
        MOVE.W  (-14112).W,D0                   ; $00896E ; scroll accel rate
        ADD.W   D0,D0                           ; $008972 ; double rate
        CMPI.W  #$0400,D0                       ; $008974 ; max accel
        BLE.S  .clamp_accel                     ; $008978
        MOVE.W  #$0400,D0                       ; $00897A
.clamp_accel:
        MOVE.W  D0,(-14112).W                   ; $00897E ; store updated rate
        ADD.W  (-14120).W,D0                    ; $008982 ; scroll_pos += rate
        CMPI.W  #$7800,D0                       ; $008986 ; max scroll = $7800
        BLE.S  .clamp_scroll_max                ; $00898A
        MOVE.W  #$7800,D0                       ; $00898C
.clamp_scroll_max:
        MOVE.W  D0,(-14120).W                   ; $008990 ; store scroll pos
        DC.W    $6000,$FF6A         ; BRA.W  $008900; $008994 ; → common path
; --- Deceleration phase: subtract rate from scroll ---
        MOVE.W  (-14112).W,D0                   ; $008998 ; scroll decel rate
        ADD.W   D0,D0                           ; $00899C ; double rate
        CMPI.W  #$0400,D0                       ; $00899E ; max decel
        BLE.S  .clamp_decel                     ; $0089A2
        MOVE.W  #$0400,D0                       ; $0089A4
.clamp_decel:
        MOVE.W  D0,(-14112).W                   ; $0089A8 ; store updated rate
        NEG.W  D0                               ; $0089AC ; negate for subtract
        ADD.W  (-14120).W,D0                    ; $0089AE ; scroll_pos -= rate
        CMPI.W  #$0500,D0                       ; $0089B2 ; min scroll = $500
        BGE.S  .clamp_scroll_min                ; $0089B6
        MOVE.W  #$0500,D0                       ; $0089B8
.clamp_scroll_min:
        MOVE.W  D0,(-14120).W                   ; $0089BC ; store scroll pos
        DC.W    $6000,$FF3E         ; BRA.W  $008900; $0089C0 ; → common path
; --- Button handler: toggle camera mode flags ---
        BTST    #4,(-14227).W                   ; $0089C4 ; button 4 pressed?
        BEQ.S  .setup_viewport                  ; $0089CA
        BCHG    #2,(-15597).W                   ; $0089CC ; toggle alt view
        BCLR    #4,(-15597).W                   ; $0089D2 ; clear override
; --- Write viewport registers ---
.setup_viewport:
        MOVE.W  #$00C0,(-16184).W               ; $0089D8 ; viewport width=192
        MOVE.W  #$0100,$00FF60CC                ; $0089DE ; viewport scale
        MOVE.W  (-14118).W,(-16210).W           ; $0089E6 ; copy H scroll
        MOVE.W  #$0000,(-16208).W               ; $0089EC ; clear V scroll
        MOVE.W  #$0000,(-16206).W               ; $0089F2 ; clear scroll param
        MOVE.W  (-14116).W,(-16300).W           ; $0089F8 ; write X render pos
        MOVE.W  (-14114).W,(-16298).W           ; $0089FE ; write Y render pos
; --- Jump table dispatch by camera mode ---
        MOVE.W  (-14176).W,D0                   ; $008A04 ; camera mode index
        MOVEA.L $008A0E(PC,D0.W),A1             ; $008A08 ; load handler addr
        JMP     (A1)                            ; $008A0C ; dispatch
; jump table (8 entries, longword pointers)
        DC.W    $0088                           ; $008A0E
        OR.W   $0088(A0),D5                     ; $008A10
        OR.B   -(A6),D5                         ; $008A14
        DC.W    $0088                           ; $008A16
        OR.W   $0088(A0),D5                     ; $008A18
        OR.W   $0088(A0),D5                     ; $008A1C
        or.w    d2,d5                   ; $8A42
        DC.W    $0088                           ; $008A22
        OR.W   $1028(A0),D5                     ; $008A24
        DC.W    $00E5                           ; $008A28
; --- Camera mode handler: segment-based proximity search ---
        BTST    #2,D0                           ; $008A2A ; flag bit 2?
        DC.W    $6600,$014C         ; BNE.W  $008B7C; $008A2E ; → alt handler
        CMPI.W  #$00E0,$001C(A0)                ; $008A32 ; height > 224?
        BLE.S  .check_override                  ; $008A38
        ANDI.B  #$02,D0                         ; $008A3A ; flag bit 1?
        DC.W    $6600,$013C         ; BNE.W  $008B7C; $008A3E ; → alt handler
; check if entity is in track segment range $42-$47
        MOVE.W  $0024(A0),D0                    ; $008A42 ; segment index
        CMPI.W  #$0042,D0                       ; $008A46 ; seg < $42?
        BCS.S  .check_override                  ; $008A4A
        CMPI.W  #$0048,D0                       ; $008A4C ; seg >= $48?
        BCC.S  .check_override                  ; $008A50
; special segment: use hardcoded table
        lea     state_handler_table_init+52(pc),a1; $43FA $0108 ; default table
        BTST    #2,(-15597).W                   ; $008A56 ; alt view?
        BEQ.S  .use_default_table               ; $008A5C
        lea     state_handler_table_init+68(pc),a1; $43FA $010C ; alt table
.use_default_table:
        LEA     (-16198).W,A2                   ; $008A62 ; dest buffer
        BRA.S  .entry_found                     ; $008A66
; --- Check for pointer override ---
.check_override:
        BTST    #4,(-15597).W                   ; $008A68 ; forced entry?
        BEQ.S  .load_state_table                ; $008A6E
        MOVEA.L (-15736).W,A1                   ; $008A70 ; cached entry ptr
        BRA.S  .entry_found                     ; $008A74
; --- Load state table and search for nearest waypoint ---
.load_state_table:
        MOVEQ   #$00,D0                         ; $008A76
        BTST    #2,(-15597).W                   ; $008A78 ; alt view mode?
        BEQ.S  .select_entry                    ; $008A7E
        MOVEQ   #$04,D0                         ; $008A80 ; offset to alt table
.select_entry:
        LEA     $00FF301A,A1                    ; $008A82 ; state table base
        ADD.W  (-14176).W,D0                    ; $008A88 ; + mode*2
        ADD.W  (-14176).W,D0                    ; $008A8C ; (doubled for longwords)
        MOVEA.L $00(A1,D0.W),A1                 ; $008A90 ; load table ptr
; --- Proximity search: find closest waypoint to entity ---
        LEA     (-16198).W,A2                   ; $008A94 ; output buffer
        MOVE.W  $0030(A0),D0                    ; $008A98 ; entity x_pos
        MOVE.W  $0034(A0),D1                    ; $008A9C ; entity y_pos
        MOVE.W  #$0640,D6                       ; $008AA0 ; search radius=1600
        MOVE.W  (A1)+,D7                        ; $008AA4 ; entry count
.search_loop:
        MOVE.W  $0000(A1),D2                    ; $008AA6 ; waypoint X
        MOVE.W  $0004(A1),D4                    ; $008AAA ; waypoint Y
        MOVE.W  D2,D3                           ; $008AAE
        SUB.W   D0,D3                           ; $008AB0 ; dx = wp.x - ent.x
        BPL.S  .abs_x_dist                     ; $008AB2
        NEG.W  D3                               ; $008AB4 ; |dx|
.abs_x_dist:
        CMP.W  D6,D3                            ; $008AB6 ; |dx| > radius?
        BGT.S  .next_entry                      ; $008AB8 ; skip
        MOVE.W  D4,D3                           ; $008ABA
        SUB.W   D1,D3                           ; $008ABC ; dy = wp.y - ent.y
        BPL.S  .abs_y_dist                     ; $008ABE
        NEG.W  D3                               ; $008AC0 ; |dy|
.abs_y_dist:
        CMP.W  D6,D3                            ; $008AC2 ; |dy| <= radius?
        BLE.S  .entry_found                     ; $008AC4 ; within range
.next_entry:
        LEA     $0010(A1),A1                    ; $008AC6 ; next entry (16 bytes)
        DBRA    D7,.search_loop                 ; $008ACA
        jmp     state_handler_table_init+84(pc); $4EFA $00AC ; no match → default
; --- Apply matched waypoint entry ---
.entry_found:
        BCLR    #3,(-15597).W                   ; $008AD2 ; clear music flag
        CMPA.L  (-15736).W,A1                   ; $008AD8 ; same as cached?
        BEQ.S  .same_entry                      ; $008ADC
        MOVE.L  A1,(-15736).W                   ; $008ADE ; cache new entry
        MOVE.W  $0006(A1),(-16128).W            ; $008AE2 ; store V angle
        MOVE.W  $0008(A1),(-16126).W            ; $008AE8 ; store H angle
        MOVE.W  $000A(A1),(-16124).W            ; $008AEE ; store zoom/FOV
.same_entry:
        MOVE.W  $000E(A1),D2                    ; $008AF4 ; entry flags+handler
        BTST    #15,D2                          ; $008AF8 ; music trigger bit?
        BEQ.S  .check_flag_bit                  ; $008AFC
        BSET    #3,(-15597).W                   ; $008AFE ; set music flag
.check_flag_bit:
        ANDI.W  #$7FFF,D2                       ; $008B04 ; mask off bit 15
; copy 14-byte entry to output buffer
        MOVE.L  (A1)+,(A2)+                     ; $008B08 ; bytes 0-3
        MOVE.L  (A1)+,(A2)+                     ; $008B0A ; bytes 4-7
        MOVE.L  (A1)+,(A2)+                     ; $008B0C ; bytes 8-11
        MOVE.W  (A1),(A2)                       ; $008B0E ; bytes 12-13
        MOVE.W  (A1),D0                         ; $008B10 ; render param
        ADD.W   D0,D0                           ; $008B12 ; *2
        ADD.W  D0,$00FF60CC                     ; $008B14 ; accumulate scale
; dispatch sub-handler via jump table
        MOVEA.L $008B28(PC,D2.W),A1             ; $008B1A ; handler from table
        JSR     (A1)                            ; $008B1E ; call sub-handler
        BCLR    #1,(-15597).W                   ; $008B20 ; clear update flag
        RTS                                     ; $008B26
