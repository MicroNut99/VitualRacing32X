; ============================================================================
; FM Instrument Setup — load instrument data and configure channels
; ROM Range: $03061C-$03078C (368 bytes)
; ============================================================================
; Loads instrument definition from ROM table at $032AB8 (indexed by D7-$81).
; Instrument header: +$00=seq offset, +$02=FM count, +$03=PSG count,
; +$04=tempo, +$05=multiplier. Sets up FM channels ($0040+N*$30 in A6)
; with sequence pointers, register assignments from table at $03078C,
; panning ($C0), and initial frequency. Then sets up PSG channels ($0190+).
; Iterates existing effect channels ($0220, 6 entries) to set key-off flags.
; Finally calls fm_init_channel for FM and fm_set_volume for PSG channels
; not marked key-off. Silences unused PSG noise channel. Pops return addr.
;
; Entry: A6 = sound driver state pointer
; Entry: D7 = sound command byte ($81-$9F)
; Uses: D0, D1, D4, D5, D6, D7, A0, A1, A2, A3, A4, A5
; Calls:
;   $030C8A: fm_init_channel
;   $030CBA: fm_write_wrapper
;   $030D1C: z80_bus_request
;   $030FB2: fm_set_volume
; Confidence: high
; ============================================================================

; --- Clear sound buffer, load instrument from ROM ---
fm_instrument_setup:
        jsr     sound_buffer_clear(pc)  ; $4EBA $05C2
        DC.W    $49FA,$2496         ; LEA     $032AB8(PC),A4; $030620 ; instrument table
        SUBI.B  #$81,D7                         ; $030624 ; cmd $81→idx 0
        LSL.W  #2,D7                            ; $030628 ; *4 (longword ptrs)
        MOVEA.L $00(A4,D7.W),A4                 ; $03062A ; instrument data ptr
; parse instrument header
        MOVEQ   #$00,D0                         ; $03062E
        MOVE.W  (A4),D0                         ; $030630 ; +$00: seq offset
        ADD.L  A4,D0                            ; $030632 ; absolute seq addr
        MOVE.L  D0,$0030(A6)                    ; $030634 ; store seq pointer
        MOVE.B  $0005(A4),$0002(A6)             ; $030638 ; +$05: multiplier → tempo
        MOVE.B  $0005(A4),$0001(A6)             ; $03063E ; multiplier → speed
; setup loop variables
        MOVEQ   #$00,D1                         ; $030644 ; panning accum
        MOVEA.L A4,A3                           ; $030646 ; save header base
        ADDQ.W  #6,A4                           ; $030648 ; skip 6-byte header
; --- FM channel setup ---
        MOVEQ   #$00,D7                         ; $03064A
        MOVE.B  $0002(A3),D7                    ; $03064C ; +$02: FM chan count
        BEQ.S  .setup_psg                       ; $030650 ; no FM channels
        SUBQ.B  #1,D7                           ; $030652 ; for DBRA
        MOVE.B  #$C0,D1                         ; $030654 ; pan reg base ($C0)
        MOVE.B  $0004(A3),D4                    ; $030658 ; +$04: tempo divider
        MOVEQ   #$30,D6                         ; $03065C ; channel struct size
        MOVE.B  #$01,D5                         ; $03065E ; initial freq mult
        LEA     $0040(A6),A1                    ; $030662 ; FM ch0 base (A6+$40)
        lea     fm_channel_reg_map_instrument_loader_b(pc),a2; $45FA $0124 ; reg map
.fm_channel_loop:
        BSET    #7,(A1)                         ; $03066A ; mark channel active
        MOVE.B  (A2)+,$0001(A1)                 ; $03066E ; FM register number
        MOVE.B  D4,$0002(A1)                    ; $030672 ; tempo divider
        MOVE.B  D6,$000D(A1)                    ; $030676 ; struct stride ($30)
        MOVE.B  D1,$0027(A1)                    ; $03067A ; panning ($C0)
        MOVE.B  D5,$000E(A1)                    ; $03067E ; freq multiplier
; load sequence pointer (relative to header)
        MOVEQ   #$00,D0                         ; $030682
        MOVE.W  (A4)+,D0                        ; $030684 ; seq offset
        ADD.L  A3,D0                            ; $030686 ; + header base
        MOVE.L  D0,$0004(A1)                    ; $030688 ; store seq ptr
        MOVE.W  (A4)+,$0008(A1)                 ; $03068C ; initial frequency
        ADDA.W  D6,A1                           ; $030690 ; next chan struct
        DBRA    D7,.fm_channel_loop             ; $030692
; --- DAC mode check (7 FM channels = DAC) ---
        CMPI.B  #$07,$0002(A3)                  ; $030696 ; 7 channels?
        BNE.S  .not_dac_mode                    ; $03069C
        MOVEQ   #$2B,D0                         ; $03069E ; DAC enable reg
        MOVEQ   #$00,D1                         ; $0306A0 ; DAC off
        jsr     fm_write_wrapper(pc)    ; $4EBA $0616
        BRA.S  .setup_psg                       ; $0306A6
; --- Normal FM: key-off ch6, set panning ---
.not_dac_mode:
        MOVEQ   #$28,D0                         ; $0306A8 ; key on/off reg
        MOVEQ   #$06,D1                         ; $0306AA ; ch6 key-off
        jsr     fm_write_wrapper(pc)    ; $4EBA $060C
        MOVE.B  #$B6,D0                         ; $0306B0 ; pan/feedback reg ch3P2
        MOVE.B  #$C0,D1                         ; $0306B4 ; L+R stereo
        jsr     z80_bus_wait(pc)        ; $4EBA $0662 ; request Z80 bus
        jsr     fm_write_port_0_1+10(pc); $4EBA $0640 ; write to FM port 1
        MOVE.W  #$0000,Z80_BUSREQ                ; $0306C0 ; release Z80 bus
; --- PSG channel setup ---
.setup_psg:
        MOVEQ   #$00,D7                         ; $0306C8
        MOVE.B  $0003(A3),D7                    ; $0306CA ; +$03: PSG chan count
        BEQ.S  .check_effects                   ; $0306CE ; no PSG channels
        SUBQ.B  #1,D7                           ; $0306D0 ; for DBRA
        LEA     $0190(A6),A1                    ; $0306D2 ; PSG ch0 (A6+$190)
        lea     fm_channel_reg_map_instrument_loader_b+8(pc),a2; $45FA $00BC ; PSG reg map
.psg_channel_loop:
        BSET    #7,(A1)                         ; $0306DA ; mark active
        MOVE.B  (A2)+,$0001(A1)                 ; $0306DE ; PSG register num
        MOVE.B  D4,$0002(A1)                    ; $0306E2 ; tempo
        MOVE.B  D6,$000D(A1)                    ; $0306E6 ; struct stride
        MOVE.B  D5,$000E(A1)                    ; $0306EA ; freq multiplier
        MOVEQ   #$00,D0                         ; $0306EE
        MOVE.W  (A4)+,D0                        ; $0306F0 ; seq offset
        ADD.L  A3,D0                            ; $0306F2 ; + header base
        MOVE.L  D0,$0004(A1)                    ; $0306F4 ; store seq ptr
        MOVE.W  (A4)+,$0008(A1)                 ; $0306F8 ; initial freq
        MOVE.B  (A4)+,$000A(A1)                 ; $0306FC ; volume
        MOVE.B  (A4)+,$000B(A1)                 ; $030700 ; envelope
        ADDA.W  D6,A1                           ; $030704 ; next chan struct
        DBRA    D7,.psg_channel_loop             ; $030706
; --- Mark conflicting effect channels for key-off ---
.check_effects:
        LEA     $0220(A6),A1                    ; $03070A ; SFX channels (A6+$220)
        MOVEQ   #$05,D7                         ; $03070E ; 6 effect slots
.effect_loop:
        TST.B  (A1)                             ; $030710 ; slot active? (bit 7)
        BPL.W  .next_effect                     ; $030712 ; inactive, skip
        MOVEQ   #$00,D0                         ; $030716
        MOVE.B  $0001(A1),D0                    ; $030718 ; effect reg number
        BMI.S  .calc_psg_offset                 ; $03071C ; bit 7 = PSG
; FM effect: (reg - 2) * 4 → pointer table index
        SUBQ.B  #2,D0                           ; $03071E
        LSL.B  #2,D0                            ; $030720 ; *4
        BRA.S  .lookup_pointer                  ; $030722
; PSG effect: reg >> 3 → pointer table index
.calc_psg_offset:
        LSR.B  #3,D0                            ; $030724 ; /8
.lookup_pointer:
        lea     fm_channel_pointer_table_sfx_loader(pc),a0; $41FA $012A ; chan ptr table
        MOVEA.L $00(A0,D0.W),A0                 ; $03072A ; target channel
        BSET    #2,(A0)                         ; $03072E ; set key-off flag
.next_effect:
        ADDA.W  D6,A1                           ; $030732 ; next effect slot
        DBRA    D7,.effect_loop                 ; $030734
; check extra SFX slots for key-off
        TST.W  $0340(A6)                        ; $030738 ; SFX slot $340 active?
        BPL.S  .check_sfx_0370                  ; $03073C
        BSET    #2,$0100(A6)                    ; $03073E ; key-off FM ch at $100
.check_sfx_0370:
        TST.W  $0370(A6)                        ; $030744 ; SFX slot $370 active?
        BPL.S  .fm_init_loop                    ; $030748
        BSET    #2,$01F0(A6)                    ; $03074A ; key-off PSG ch at $1F0
; --- Initialize all FM channels (skip key-off ones) ---
.fm_init_loop:
        LEA     $0070(A6),A5                    ; $030750 ; FM ch1 (skip ch0)
        MOVEQ   #$05,D4                         ; $030754 ; 6 FM channels
.fm_init_next:
        BTST    #2,(A5)                         ; $030756 ; key-off flag set?
        BNE.S  .skip_fm_init                    ; $03075A ; skip this channel
        jsr     fm_init_channel(pc)     ; $4EBA $052C
.skip_fm_init:
        ADDA.W  D6,A5                           ; $030760 ; next ($30 bytes)
        DBRA    D4,.fm_init_next                ; $030762
; --- Initialize PSG channels ---
        MOVEQ   #$02,D4                         ; $030766 ; 3 PSG channels
.psg_init_loop:
        BTST    #2,(A5)                         ; $030768 ; key-off flag?
        BNE.S  .skip_psg_init                   ; $03076C
        jsr     psg_set_pos_silence+16(pc); $4EBA $0842 ; set PSG volume
.skip_psg_init:
        ADDA.W  D6,A5                           ; $030772 ; next channel
        DBRA    D4,.psg_init_loop               ; $030774
; silence noise channel if not key-off
        BTST    #2,$01F0(A6)                    ; $030778 ; noise ch key-off?
        BNE.S  .done                            ; $03077E
        MOVE.B  #$FF,PSG                  ; $030780 ; PSG: all silent
; pop return address (caller won't resume)
.done:
        ADDQ.W  #4,A7                           ; $030788 ; skip return addr
        RTS                                     ; $03078A
