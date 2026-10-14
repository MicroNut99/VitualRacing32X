; ============================================================================
; Display State Dispatcher — 13-state game display controller
; ROM Range: $004084-$00413A (182 bytes)
; ============================================================================
; Dispatches to one of 13 display states via jump table indexed by RAM $C07C.
; State 0 ($0040C8): Initializes display system — sets adapter flag,
;   clears display/race mode flags ($FF6960/$FF6930/$FF6970), configures
;   HUD geometry (A2=$FF6754: offset=$FFE0, size=$0040, Y=$F600),
;   sets camera texture pointer, advances state counter.
; State 1 ($00412E): Sets sound command byte $96, advances state.
; Remaining states dispatch to handlers outside this function.
;
; Uses: D0, A0, A1, A2
; RAM:
;   $C07C: display state index (advanced by 4 per transition)
; Confidence: high
; ============================================================================

display_state_disp_004084:
        MOVE.W  #$0001,(-16312).W               ; $004084
        MOVE.W  (-16260).W,D0                   ; $00408A
        MOVEA.L .jump_table(PC,D0.W),A1          ; $00408E
        JMP     (A1)                            ; $004092
; --- Display state jump table (13 entries at $004094) ---
; Indexed by $C07C (0/4/8/.../48). Each entry is a 68K absolute address.
.jump_table:
        dc.l    $008840C8               ; [ 0] .state_0: display init (local)
        dc.l    $0088412E               ; [ 1] .state_1: sound cmd $96 (local)
        dc.l    $0088413A               ; [ 2] object speed ramp-up + state advance
        dc.l    $00884168               ; [ 3] check timeout (60 frames)
        dc.l    $0088417C               ; [ 4] race completion check + lap bit tracking
        dc.l    $008841E4               ; [ 5] display_state_race_lap_preamble
        dc.l    $008842BA               ; [ 6] timer threshold init (sprite setup)
        dc.l    $00884300               ; [ 7] scroll update animation
        dc.l    $0088432E               ; [ 8] timer wait and clear sprite
        dc.l    $0088434A               ; [ 9] fade subtract array (palette fade-out)
        dc.l    $00884390               ; [10] timer wait and set transition flags
        dc.l    $008843BC               ; [11] sound queue and advance (SH2 gate)
        dc.l    $008843D0               ; [12] game_init_state_dispatch_002
.state_0:
        MOVE.B  #$01,(-14336).W                 ; $0040C8
        CMPI.W  #$FFFF,(-16304).W               ; $0040CE
        BNE.S  .init_display                        ; $0040D4
        MOVE.W  #$0000,(-16304).W               ; $0040D6
.init_display:
        MOVE.B  #$00,$00FF6960                  ; $0040DC
        MOVE.B  #$00,$00FF6930                  ; $0040E4
        MOVE.B  #$00,$00FF6970                  ; $0040EC
        LEA     $00FF6754,A2                    ; $0040F4
        MOVE.B  #$F3,(-14302).W                 ; $0040FA
        MOVE.W  #$FFE0,$0004(A2)                ; $004100
        MOVE.W  #$0040,$0006(A2)                ; $004106
        MOVE.W  #$F600,$0008(A2)                ; $00410C
        MOVE.L  #$2229660C,$0010(A2)            ; $004112
        MOVE.W  #$0001,$0000(A2)                ; $00411A
        MOVE.W  #$0040,(-15780).W               ; $004120
        ADDQ.W  #4,(-16260).W                   ; $004126
        jmp     ai_digit_lookup_best_lap(pc); $4EFA $708C
.state_1:
        MOVE.B  #$96,(-14171).W                 ; $00412E
        ADDQ.W  #4,(-16260).W                   ; $004134
        RTS                                     ; $004138
