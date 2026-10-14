; ============================================================================
; sh2_multi_panel_tile_renderer — SH2 Multi-Panel Tile Renderer
; ROM Range: $00F8F6-$00FB24 (558 bytes)
; Data prefix (32 bytes: default palette color data, same as
; default_palette_color_data). Renders tile overlays to SH2 framebuffer via
; sh2_cmd_27 for up to 3 screen panels. Computes tile addresses
; from palette index with bit-shift multiplication. Panel 1 renders
; main view, panel 2 renders comparison view (optional), panel 3
; renders stats overlay. Two identical rendering blocks handle
; P1 and P2 viewports.
;
; Uses: D0, D1, D2, A0, A1
; Calls: $00E3B4 (sh2_cmd_27)
; Confidence: high
; ============================================================================

; --- Data prefix: 16 palette color words (default background colors) ---
sh2_multi_panel_tile_renderer:
        DC.W    $0EEE                           ; $00F8F6 ; color 0: light gray
        DC.W    $0EEE                           ; $00F8F8 ; color 1
        DC.W    $0EEE                           ; $00F8FA ; color 2
        DC.W    $0EEE                           ; $00F8FC ; color 3
        ORI.B  #$00,D0                          ; $00F8FE ; color 4-5 (as dc.w)
        ORI.B  #$00,D0                          ; $00F902 ; color 6-7
        DC.W    $0EEE                           ; $00F906 ; color 8
        DC.W    $0EEE                           ; $00F908 ; color 9
        DC.W    $0EEE                           ; $00F90A ; color 10
        DC.W    $0EEE                           ; $00F90C ; color 11
        ORI.B  #$00,D0                          ; $00F90E ; color 12-13
        ORI.B  #$00,D0                          ; $00F912 ; color 14-15

; =====================================================
; Player 1 tile rendering
; =====================================================
; --- P1: Look up tile address from panel index ---
        MOVEQ   #$00,D0                         ; $00F916
        TST.B  (-24549).W                       ; $00F918 ; multi-panel mode?
        BNE.S  .p1_multi_panel_index             ; $00F91C
        MOVE.B  (-24551).W,D0                   ; $00F91E ; single: use main idx
        BRA.S  .p1_lookup_tile                   ; $00F922
.p1_multi_panel_index:
        MOVE.B  (-24545).W,D0                   ; $00F924 ; multi: use panel idx
.p1_lookup_tile:
; --- D0 * 6: index into tile address table ---
        LEA     $0088FB24,A1                    ; $00F928 ; tile address table
        ADD.W  D0,D0                           ; $00F92E ; D0 *= 2
        MOVE.W  D0,D1                           ; $00F930 ; save D0*2
        ADD.W  D0,D0                           ; $00F932 ; D0 *= 4
        ADD.W  D1,D0                           ; $00F934 ; D0 = orig*6
        MOVEA.L $00(A1,D0.W),A0                 ; $00F936 ; tile data address
        MOVE.W  $04(A1,D0.W),D0                 ; $00F93A ; tile count/param
; --- Render main panel via SH2 cmd 27 ---
        MOVE.W  #$0030,D1                       ; $00F93E ; tile width = 48px
        MOVE.W  #$0010,D2                       ; $00F942 ; tile height = 16px
        jsr     sh2_cmd_27(pc)          ; $4EBA $EA6C

; --- P1: Check for 2-panel mode ---
        MOVEQ   #$00,D0                         ; $00F94A
        CMPI.B  #$01,(-24549).W                 ; $00F94C ; 2-panel mode?
        BNE.S  .p1_not_2panel                    ; $00F952
; --- P1 panel 2: secondary viewport ---
        MOVEA.L #$04012024,A0                   ; $00F954 ; framebuf offset P1.2
        MOVE.W  #$0060,D0                       ; $00F95A ; X offset = 96
        MOVE.W  #$0010,D1                       ; $00F95E ; width 16
        MOVE.W  #$0010,D2                       ; $00F962 ; height 16
.p1_wait_panel2:
        TST.B  COMM0_HI                        ; $00F966 ; wait SH2 ready
        BNE.S  .p1_wait_panel2                  ; $00F96C
        jsr     sh2_cmd_27(pc)          ; $4EBA $EA44
        MOVE.B  (-24551).W,D0                   ; $00F972 ; get main palette idx
        BRA.S  .p1_render_comparison             ; $00F976
.p1_not_2panel:
        MOVE.B  (-24544).W,D0                   ; $00F978 ; alt palette index
.p1_render_comparison:
; --- P1: Render comparison view ---
        MOVEA.L #$04014014,A0                   ; $00F97C ; framebuf for compare
        TST.B  D0                               ; $00F982 ; zero = no offset
        BNE.S  .p1_comparison_nonzero            ; $00F984
        MOVE.W  #$0048,D0                       ; $00F986 ; default width 72
        BRA.S  .p1_comparison_params_ready       ; $00F98A
.p1_comparison_nonzero:
        ADDA.L  #$00000047,A0                   ; $00F98C ; shift FB ptr +71
        MOVE.W  #$0039,D0                       ; $00F992 ; reduced width 57
.p1_comparison_params_ready:
        MOVE.W  #$0010,D1                       ; $00F996 ; height 16
        MOVE.W  #$0010,D2                       ; $00F99A ; tile size 16
.p1_wait_comparison:
        TST.B  COMM0_HI                        ; $00F99E ; wait SH2 ready
        BNE.S  .p1_wait_comparison               ; $00F9A4
        jsr     sh2_cmd_27(pc)          ; $4EBA $EA0C

; --- P1: Check for 3-panel mode ---
        MOVEQ   #$00,D0                         ; $00F9AA
        CMPI.B  #$02,(-24549).W                 ; $00F9AC ; 3-panel mode?
        BNE.S  .p1_not_3panel                    ; $00F9B2
; --- P1 panel 3a: first half of stats ---
        MOVEA.L #$04017030,A0                   ; $00F9B4 ; framebuf stats top
        MOVE.W  #$0048,D0                       ; $00F9BA ; width 72
        MOVE.W  #$0010,D1                       ; $00F9BE ; height 16
        MOVE.W  #$0010,D2                       ; $00F9C2 ; tile 16
.p1_wait_panel3a:
        TST.B  COMM0_HI                        ; $00F9C6 ; wait SH2 ready
        BNE.S  .p1_wait_panel3a                 ; $00F9CC
        jsr     sh2_cmd_27(pc)          ; $4EBA $E9E4
; --- P1 panel 3b: second half of stats ---
        MOVEA.L #$04019018,A0                   ; $00F9D2 ; framebuf stats bottom
        MOVE.W  #$0078,D0                       ; $00F9D8 ; width 120
        MOVE.W  #$0010,D1                       ; $00F9DC ; height 16
        MOVE.W  #$0010,D2                       ; $00F9E0 ; tile 16
.p1_wait_panel3b:
        TST.B  COMM0_HI                        ; $00F9E4 ; wait SH2 ready
        BNE.S  .p1_wait_panel3b                 ; $00F9EA
        jsr     sh2_cmd_27(pc)          ; $4EBA $E9C6
        MOVE.B  (-24551).W,D0                   ; $00F9F0 ; main palette idx
        BRA.S  .p1_stats_overlay                 ; $00F9F4
.p1_not_3panel:
        MOVE.B  (-24543).W,D0                   ; $00F9F6 ; stats palette idx

; --- P1: Stats overlay panel ---
; Compute framebuffer address with D0*24 offset for stats row
.p1_stats_overlay:
        MOVE.B  D0,D2                           ; $00F9FA ; save palette idx
        MOVEA.L #$0401B018,A0                   ; $00F9FC ; framebuf stats base
        ADD.W  D0,D0                           ; $00FA02 ; D0 *= 2
        ADD.W  D0,D0                           ; $00FA04 ; D0 *= 4
        ADD.W  D0,D0                           ; $00FA06 ; D0 *= 8
        MOVE.W  D0,D1                           ; $00FA08 ; save D0*8
        ADD.W  D0,D0                           ; $00FA0A ; D0 *= 16
        ADD.W  D1,D0                           ; $00FA0C ; D0 = orig*24
        LEA     $00(A0,D0.W),A0                 ; $00FA0E ; offset framebuf ptr
        MOVE.W  #$0018,D0                       ; $00FA12 ; width 24
        TST.B  D2                               ; $00FA16 ; palette idx zero?
        BEQ.W  .p1_stats_params_ready            ; $00FA18
        SUBQ.L  #1,A0                           ; $00FA1C ; adjust ptr -1
        MOVE.W  #$0019,D0                       ; $00FA1E ; width 25
.p1_stats_params_ready:
        MOVE.W  #$0010,D1                       ; $00FA22 ; height 16
        MOVE.W  #$0010,D2                       ; $00FA26 ; tile 16
.p1_wait_stats:
        TST.B  COMM0_HI                        ; $00FA2A ; wait SH2 ready
        BNE.S  .p1_wait_stats                   ; $00FA30
        jsr     sh2_cmd_27(pc)          ; $4EBA $E980

; =====================================================
; Player 2 tile rendering (mirrors P1 logic)
; =====================================================
; --- P2: Check 2-panel mode ---
        MOVEQ   #$00,D0                         ; $00FA36
        CMPI.B  #$01,(-24548).W                 ; $00FA38 ; P2 2-panel mode?
        BNE.S  .p2_not_2panel                    ; $00FA3E
; --- P2 panel 2 ---
        MOVEA.L #$040120BC,A0                   ; $00FA40 ; P2 framebuf offset
        MOVE.W  #$0060,D0                       ; $00FA46 ; X offset 96
        MOVE.W  #$0010,D1                       ; $00FA4A
        MOVE.W  #$0010,D2                       ; $00FA4E
.p2_wait_panel2:
        TST.B  COMM0_HI                        ; $00FA52 ; wait SH2 ready
        BNE.S  .p2_wait_panel2                  ; $00FA58
        jsr     sh2_cmd_27(pc)          ; $4EBA $E958
        MOVE.B  (-24550).W,D0                   ; $00FA5E ; P2 palette idx
        BRA.S  .p2_render_comparison             ; $00FA62
.p2_not_2panel:
        MOVE.B  (-24542).W,D0                   ; $00FA64 ; P2 alt palette
.p2_render_comparison:
; --- P2: Comparison panel ---
        MOVEA.L #$040140AC,A0                   ; $00FA68 ; P2 compare framebuf
        TST.B  D0                               ; $00FA6E
        BNE.S  .p2_comparison_nonzero            ; $00FA70
        MOVE.W  #$0048,D0                       ; $00FA72 ; width 72
        BRA.S  .p2_comparison_params_ready       ; $00FA76
.p2_comparison_nonzero:
        ADDA.L  #$00000047,A0                   ; $00FA78 ; shift +71
        MOVE.W  #$0039,D0                       ; $00FA7E ; width 57
.p2_comparison_params_ready:
        MOVE.W  #$0010,D1                       ; $00FA82
        MOVE.W  #$0010,D2                       ; $00FA86
.p2_wait_comparison:
        TST.B  COMM0_HI                        ; $00FA8A ; wait SH2 ready
        BNE.S  .p2_wait_comparison               ; $00FA90
        jsr     sh2_cmd_27(pc)          ; $4EBA $E920

; --- P2: Check 3-panel mode ---
        MOVEQ   #$00,D0                         ; $00FA96
        CMPI.B  #$02,(-24548).W                 ; $00FA98 ; P2 3-panel?
        BNE.S  .p2_not_3panel                    ; $00FA9E
; --- P2 panel 3a ---
        MOVEA.L #$040170C8,A0                   ; $00FAA0 ; P2 stats top
        MOVE.W  #$0048,D0                       ; $00FAA6 ; width 72
        MOVE.W  #$0010,D1                       ; $00FAAA
        MOVE.W  #$0010,D2                       ; $00FAAE
.p2_wait_panel3a:
        TST.B  COMM0_HI                        ; $00FAB2 ; wait SH2 ready
        BNE.S  .p2_wait_panel3a                 ; $00FAB8
        jsr     sh2_cmd_27(pc)          ; $4EBA $E8F8
; --- P2 panel 3b ---
        MOVEA.L #$040190B0,A0                   ; $00FABE ; P2 stats bottom
        MOVE.W  #$0078,D0                       ; $00FAC4 ; width 120
        MOVE.W  #$0010,D1                       ; $00FAC8
        MOVE.W  #$0010,D2                       ; $00FACC
.p2_wait_panel3b:
        TST.B  COMM0_HI                        ; $00FAD0 ; wait SH2 ready
        BNE.S  .p2_wait_panel3b                 ; $00FAD6
        jsr     sh2_cmd_27(pc)          ; $4EBA $E8DA
        MOVE.B  (-24550).W,D0                   ; $00FADC ; P2 palette idx
        BRA.S  .p2_stats_overlay                 ; $00FAE0
.p2_not_3panel:
        MOVE.B  (-24541).W,D0                   ; $00FAE2 ; P2 stats palette

; --- P2: Stats overlay (D0*24 offset, same as P1) ---
.p2_stats_overlay:
        MOVE.B  D0,D2                           ; $00FAE6 ; save idx
        MOVEA.L #$0401B0B0,A0                   ; $00FAE8 ; P2 stats base
        ADD.W  D0,D0                           ; $00FAEE ; D0 *= 2
        ADD.W  D0,D0                           ; $00FAF0 ; D0 *= 4
        ADD.W  D0,D0                           ; $00FAF2 ; D0 *= 8
        MOVE.W  D0,D1                           ; $00FAF4 ; save D0*8
        ADD.W  D0,D0                           ; $00FAF6 ; D0 *= 16
        ADD.W  D1,D0                           ; $00FAF8 ; D0 = orig*24
        LEA     $00(A0,D0.W),A0                 ; $00FAFA ; offset framebuf ptr
        MOVE.W  #$0018,D0                       ; $00FAFE ; width 24
        TST.B  D2                               ; $00FB02 ; zero idx?
        BEQ.W  .p2_stats_params_ready            ; $00FB04
        SUBQ.L  #1,A0                           ; $00FB08 ; adjust ptr -1
        MOVE.W  #$0019,D0                       ; $00FB0A ; width 25
.p2_stats_params_ready:
        MOVE.W  #$0010,D1                       ; $00FB0E ; height 16
        MOVE.W  #$0010,D2                       ; $00FB12 ; tile 16
.p2_wait_stats:
        TST.B  COMM0_HI                        ; $00FB16 ; wait SH2 ready
        BNE.S  .p2_wait_stats                   ; $00FB1C
        jsr     sh2_cmd_27(pc)          ; $4EBA $E894
        RTS                                     ; $00FB22
