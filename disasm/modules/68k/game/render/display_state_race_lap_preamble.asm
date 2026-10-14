; ============================================================================
; display_state_race_lap_preamble — Race Lap Display State Preamble
; ROM Range: $0041E4-$004201 (30 bytes, spans code_2200/code_4200 boundary)
; ============================================================================
; Display state handler #5 (dispatched from display_state_disp_004084 jump
; table when $C07C = 20). Sets race state flags, conditionally calls
; ai_digit_lookup_best_lap for digit/score rendering, then calls
; vdp_load_and_clear to load VDP table E + zero control bytes. Falls
; through into sprite_config_setup_001's main body at $004202.
;
; CROSS-BOUNDARY: The last instruction (JSR $0088CA20 = vdp_load_and_clear)
; is 6 bytes, but only 4 bytes fit in code_2200 ($0041FC-$0041FF). The
; remaining 2 bytes ($CA20) are at $004200 in code_4200 — the same bytes
; labeled as sprite_config_setup_001's entry point (AND.B -(A0),D5). That
; AND.B instruction is never executed; it exists only as the JSR's address
; field. After JSR returns, execution continues at $004202 (MOVEQ #$07,D7).
;
; Entry: JMP from display_state_disp_004084 (jump table at $0040A8)
; Exit: falls through to $004202 (sprite_config_setup_001 body)
; Uses: D0, D1, D5, D7, A0, A1, A2, A3 (via callees)
; Calls: ai_digit_lookup_best_lap ($00B1B8), vdp_load_and_clear ($00CA20)
; RAM:
;   $C800: race state flag (byte, set to $01)
;   $C822: timer/counter value (byte, set to $F3)
;   $C30E: display condition flags (byte, bit 5 checked)
; ============================================================================

display_state_race_lap_preamble:
        move.b  #$01,($FFFFC800).w              ; $0041E4  set race state flag
        move.b  #$F3,($FFFFC822).w              ; $0041EA  set timer/counter value
        btst    #5,($FFFFC30E).w                ; $0041F0  check display condition
        bne.s   .skip_digit_lookup              ; $0041F6  skip if already set
        jsr     ai_digit_lookup_best_lap(pc)    ; $0041F8  update digit display + best lap
.skip_digit_lookup:
; --- Cross-boundary JSR $0088CA20 (vdp_load_and_clear) ---
; Only the first 4 bytes of this 6-byte instruction fit in code_2200.
; The address low word ($CA20) is at $004200 in code_4200.
        dc.w    $4EB9,$0088                     ; $0041FC  JSR $0088CA20 (partial — see above)
