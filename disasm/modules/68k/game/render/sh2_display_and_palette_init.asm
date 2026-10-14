; ============================================================================
; sh2_display_and_palette_init — SH2 Display and Palette Initialization
; ROM Range: $00D482-$00D7B2 (816 bytes)
; Major scene initialization orchestrator. Data prefix (8 bytes).
; Configures 32X VDP mode, clears framebuffer and CRAM via DMA.
; Loads SH2 palette data, sends graphics tile commands, transfers
; compressed data to SH2 memory via sh2_send_cmd_wait. Configures
; overlay graphics with split-screen support. Sets MARS interrupts,
; VDP mode, and initializes SH2 communication via COMM0/COMM1.
;
; Uses: D0, D1, D2, D3, D4, A0, A1, A5
; Calls: $00E1BC (sh2_palette_load), $00E22C (sh2_graphics_cmd),
;        $00E2F0 (sh2_load_data), $00E316 (sh2_send_cmd_wait)
; Confidence: high
; ============================================================================

; --- Data prefix: 4 entry point offset words ---
sh2_display_and_palette_init:
        DC.W    $0088                           ; $00D482 ; offset ptr 0
        DC.W    $0088                           ; $00D484 ; offset ptr 1
        DC.W    $00DC                           ; $00D486 ; offset ptr 2
        DC.W    $0130                           ; $00D488 ; offset ptr 3

; --- Entry point selection: determine display mode ---
        CLR.B  (-24540).W                       ; $00D48A ; split_screen_flag = 0
        MOVE.B  (-347).W,(-24551).W             ; $00D48E ; palette index = default
        BTST    #7,(-600).W                     ; $00D494 ; overlay mode flag?
        BEQ.S  .mode_selected                        ; $00D49A
        MOVE.B  (-346).W,(-24551).W             ; $00D49C ; palette = overlay
        BRA.S  .mode_selected                        ; $00D4A2
; --- Split-screen entry (2P) ---
        MOVE.B  #$01,(-24540).W                 ; $00D4A4 ; split_screen = 1
        MOVE.B  (-345).W,(-24551).W             ; $00D4AA ; palette = split P1
        MOVE.B  (-344).W,(-24538).W             ; $00D4B0 ; palette = split P2
        BRA.S  .mode_selected                        ; $00D4B6
; --- 3-panel entry ---
        MOVE.B  (-341).W,(-24551).W             ; $00D4B8 ; palette = 3-panel
        MOVE.B  (-340).W,(-24538).W             ; $00D4BE ; alt palette
        MOVE.B  #$02,(-24540).W                 ; $00D4C4 ; split_screen = 2

; --- Shared initialization ---
.mode_selected:
        MOVE.W  #$002C,$00FF0008                ; $00D4CA ; set display timing
        MOVE.W  #$002C,(-14214).W               ; $00D4D2 ; store timing copy
        BCLR    #6,(-14219).W                   ; $00D4D8 ; clear interlace bit
        MOVE.W  (-14220).W,(A5)                 ; $00D4DE ; write VDP reg cache
; --- Configure 32X MARS hardware ---
        MOVE.W  #$0083,MARS_SYS_INTCTL                ; $00D4E2 ; enable MARS ints
        ANDI.B  #$FC,MARS_VDP_MODE+1                  ; $00D4EA ; clear mode bits 0-1
        JSR     $008826C8                       ; $00D4F2 ; clear MARS framebuffer
        MOVE.L  #$000A0907,D0                   ; $00D4F8 ; VDP config params
        JSR     $008814BE                       ; $00D4FE ; write VDP registers
        MOVE.B  #$01,(-14323).W                 ; $00D504 ; mark init active

; --- Copy ROM table to work RAM ---
        LEA     $0088D832,A0                    ; $00D50A ; ROM source table
        LEA     $00FF2000,A1                    ; $00D510 ; work RAM dest
        MOVE.W  #$0004,D0                       ; $00D516 ; 5 iterations
.copy_table_data:
        MOVE.W  (A0)+,(A1)+                     ; $00D51A ; 10 bytes/iter
        MOVE.W  (A0)+,(A1)+                     ; $00D51C
        MOVE.W  (A0)+,(A1)+                     ; $00D51E
        MOVE.W  (A0)+,(A1)+                     ; $00D520
        MOVE.W  (A0)+,(A1)+                     ; $00D522
        DBRA    D0,.copy_table_data                    ; $00D524

; --- Clear work RAM buffers ---
        MOVEQ   #$00,D0                         ; $00D528
        LEA     (-31616).W,A0                   ; $00D52A ; score buffer
        MOVEQ   #$1F,D1                         ; $00D52E ; 32 longwords = 128B
.clear_buffer_a:
        MOVE.L  D0,(A0)+                        ; $00D530
        DBRA    D1,.clear_buffer_a                    ; $00D532
        LEA     $00FF7B80,A0                    ; $00D536 ; display list buffer
        MOVEQ   #$7F,D1                         ; $00D53C ; 128 longwords = 512B
.clear_buffer_b:
        MOVE.L  D0,(A0)+                        ; $00D53E
        DBRA    D1,.clear_buffer_b                    ; $00D540

; --- Clear entire VDP VRAM ---
        MOVE.L  #$60000002,(A5)                 ; $00D544 ; VRAM write addr $6000
        MOVE.W  #$17FF,D1                       ; $00D54A ; 6144 longwords = 24KB
.clear_vram:
        MOVE.L  D0,(A6)                         ; $00D54E ; write to VDP data port
        DBRA    D1,.clear_vram                    ; $00D550

        JSR     $008849AA                       ; $00D554 ; wait VDP ready
; --- Clear rendering state ---
        CLR.W  (-14208).W                       ; $00D55A ; h_scroll = 0
        CLR.W  (-14206).W                       ; $00D55E ; v_scroll = 0
        CLR.W  (-32768).W                       ; $00D562 ; scroll buf A
        CLR.W  (-32766).W                       ; $00D566 ; scroll buf B
        CLR.W  (-24558).W                       ; $00D56A ; panel config
        CLR.B  (-24552).W                       ; $00D56E ; palette state
        JSR     $008849AA                       ; $00D572 ; wait VDP ready

; --- Set up rendering configuration ---
        MOVE.L  #$008BB4FC,(-13972).W           ; $00D578 ; ROM pointer table
        MOVE.B  #$01,(-14327).W                 ; $00D580 ; enable flag A
        MOVE.B  #$01,(-14326).W                 ; $00D586 ; enable flag B
        BSET    #6,(-14322).W                   ; $00D58C ; set render bit 6
        MOVE.B  #$01,(-14334).W                 ; $00D592 ; DMA enable
        MOVE.W  #$0001,(-24532).W               ; $00D598 ; active panel count

; --- Clear 4KB tile work buffer ---
        LEA     $00FF1000,A0                    ; $00D59E ; tile work buffer
        MOVE.W  #$037F,D0                       ; $00D5A4 ; 896 longwords = 3.5KB
.clear_work_buffer:
        CLR.L  (A0)+                            ; $00D5A8
        DBRA    D0,.clear_work_buffer                    ; $00D5AA

; --- Load SH2 palette data ---
        DC.W    $4EBA,$0C0C         ; JSR     $00E1BC(PC); $00D5AE ; sh2_palette_load

; --- Set priority bit on overlay palette ---
        BCLR    #7,MARS_VDP_MODE+1                    ; $00D5B2 ; clear bitmap mode
        LEA     $00FF6E00,A0                    ; $00D5BA ; CRAM buffer base
        ADDA.L  #$00000160,A0                   ; $00D5C0 ; +352 = overlay palette
        LEA     $0088D7B2,A1                    ; $00D5C6 ; ROM palette source
        MOVE.W  #$003F,D0                       ; $00D5CC ; 64 colors
.copy_palette_with_priority:
        MOVE.W  (A1)+,D1                        ; $00D5D0
        BSET    #15,D1                          ; $00D5D2 ; set priority bit
        MOVE.W  D1,(A0)+                        ; $00D5D6
        DBRA    D0,.copy_palette_with_priority                    ; $00D5D8

; --- Transfer compressed tile data to SH2 SDRAM ---
        LEA     $000E8000,A0                    ; $00D5DC ; ROM src: main tiles
        MOVEA.L #$06037000,A1                   ; $00D5E2 ; SH2 dest in SDRAM
        DC.W    $6100,$0D2C         ; BSR.W  $00E316; $00D5E8 ; sh2_send_cmd_wait

; --- Optional overlay command if flag set ---
        BTST    #7,(-600).W                     ; $00D5EC ; overlay mode?
        BEQ.S  .skip_overlay_cmd                        ; $00D5F2
.wait_comm_ready:
        TST.B  COMM0_HI                        ; $00D5F4 ; poll SH2 busy flag
        BNE.S  .wait_comm_ready                        ; $00D5FA
        MOVE.B  #$2E,COMM0_LO                  ; $00D5FC ; cmd $2E = overlay load
        MOVE.B  #$01,COMM0_HI                  ; $00D604 ; trigger SH2 dispatch
.skip_overlay_cmd:

; --- Transfer more tile data blocks ---
        LEA     $000E8C00,A0                    ; $00D60C ; ROM src: tile set 2
        MOVEA.L #$0603D100,A1                   ; $00D612 ; SH2 SDRAM dest
        DC.W    $6100,$0CFC         ; BSR.W  $00E316; $00D618 ; sh2_send_cmd_wait

; --- Branch: single vs split-screen ---
        TST.B  (-24540).W                       ; $00D61C ; split_screen_flag
        BNE.W  .split_screen_path                        ; $00D620

; --- Single-screen tile layout ---
        LEA     $000E8A00,A0                    ; $00D624 ; name table data
        MOVEA.L #$0603B600,A1                   ; $00D62A ; SH2 dest
        DC.W    $6100,$0CE4         ; BSR.W  $00E316; $00D630 ; sh2_send_cmd_wait
        LEA     $000EB980,A0                    ; $00D634 ; extended tile data
        MOVEA.L #$0603DA00,A1                   ; $00D63A ; SH2 dest
        DC.W    $6100,$0CD4         ; BSR.W  $00E316; $00D640 ; sh2_send_cmd_wait
; --- Configure single-screen graphics ---
        MOVE.W  #$0001,D0                       ; $00D644 ; panel ID = 1
        MOVE.W  #$0001,D1                       ; $00D648 ; start col = 1
        MOVE.W  #$0001,D2                       ; $00D64C ; start row = 1
        MOVE.W  #$0026,D3                       ; $00D650 ; width = 38 tiles
        MOVE.W  #$001A,D4                       ; $00D654 ; height = 26 tiles
        LEA     $00FF1000,A0                    ; $00D658 ; work buffer
        jsr     sh2_graphics_cmd(pc)    ; $4EBA $0BCC
        LEA     $00FF1000,A0                    ; $00D662
        jsr     sh2_load_data(pc)       ; $4EBA $0C86
        BRA.W  .graphics_loaded                        ; $00D66C

; --- Split-screen tile layout ---
.split_screen_path:
        LEA     $000E8E10,A0                    ; $00D670 ; split name table
        MOVEA.L #$0603B600,A1                   ; $00D676 ; SH2 dest
        DC.W    $6100,$0C98         ; BSR.W  $00E316; $00D67C ; sh2_send_cmd_wait
        LEA     $000E8FB0,A0                    ; $00D680 ; split tile ext
        MOVEA.L #$0603DA00,A1                   ; $00D686 ; SH2 dest
        DC.W    $6100,$0C88         ; BSR.W  $00E316; $00D68C ; sh2_send_cmd_wait
; --- P1 viewport (top half) ---
        MOVE.W  #$0001,D0                       ; $00D690 ; panel 1
        MOVE.W  #$0001,D1                       ; $00D694 ; col 1
        MOVE.W  #$0001,D2                       ; $00D698 ; row 1
        MOVE.W  #$0026,D3                       ; $00D69C ; width 38
        MOVE.W  #$0016,D4                       ; $00D6A0 ; height 22 (half)
        LEA     $00FF1000,A0                    ; $00D6A4
        jsr     sh2_graphics_cmd(pc)    ; $4EBA $0B80
; --- P2 viewport (bottom half) ---
        MOVE.W  #$0002,D0                       ; $00D6AE ; panel 2
        MOVE.W  #$0001,D1                       ; $00D6B2 ; col 1
        MOVE.W  #$0017,D2                       ; $00D6B6 ; row 23
        MOVE.W  #$0026,D3                       ; $00D6BA ; width 38
        MOVE.W  #$0004,D4                       ; $00D6BE ; height 4 (status bar)
        LEA     $00FF1000,A0                    ; $00D6C2
        jsr     sh2_graphics_cmd(pc)    ; $4EBA $0B62
        LEA     $00FF1000,A0                    ; $00D6CC
        jsr     sh2_load_data(pc)       ; $4EBA $0C1C

; --- Calculate framebuffer Y offset from panel index ---
.graphics_loaded:
        CLR.B  (-24537).W                       ; $00D6D6 ; clear offset flag
        MOVEQ   #$00,D0                         ; $00D6DA
        MOVEQ   #$00,D1                         ; $00D6DC ; offset accumulator
        MOVE.B  (-335).W,D0                     ; $00D6DE ; panel row index
        BEQ.S  .offset_done                        ; $00D6E2
        SUBQ.W  #1,D0                           ; $00D6E4 ; adjust for DBRA
.accumulate_offset:
        ADDI.L  #$000003C0,D1                   ; $00D6E6 ; +960 bytes per row
        DBRA    D0,.accumulate_offset                    ; $00D6EC
.offset_done:
        ADDQ.L  #4,D1                           ; $00D6F0 ; skip header
        MOVE.L  D1,(-24536).W                   ; $00D6F2 ; store FB offset

; --- Final 32X VDP configuration ---
        JSR     $0088204A                       ; $00D6F6 ; CRAM DMA transfer
        ANDI.B  #$FC,MARS_VDP_MODE+1                  ; $00D6FC ; clear mode bits
        ORI.B  #$01,MARS_VDP_MODE+1                   ; $00D704 ; set 256-color mode
        MOVE.W  #$8083,MARS_SYS_INTCTL                ; $00D70C ; enable V-INT + H-INT
        BSET    #6,(-14219).W                   ; $00D714 ; set interlace bit
        MOVE.W  (-14220).W,(A5)                 ; $00D71A ; update VDP regs
        MOVE.W  #$0020,$00FF0008                ; $00D71E ; display timing
        JSR     $00884998                       ; $00D726 ; init scroll tables

; --- Set up dispatch table pointer ---
        MOVE.W  #$0000,(-14210).W               ; $00D72C ; state counter = 0
        MOVE.L  #$0088D864,$00FF0002            ; $00D732 ; single-screen table
        TST.B  (-24540).W                       ; $00D73C ; split screen?
        BEQ.S  .dispatch_table_set                        ; $00D740
        MOVE.L  #$0088D888,$00FF0002            ; $00D742 ; split-screen table
.dispatch_table_set:

; --- Configure overlay flag ---
        MOVE.B  #$00,$00FF60D4                  ; $00D74C ; overlay off
        BTST    #7,(-600).W                     ; $00D754 ; overlay mode?
        BEQ.W  .overlay_flag_set                        ; $00D75A
        MOVE.B  #$01,$00FF60D4                  ; $00D75E ; overlay on
.overlay_flag_set:

; --- Clear sprite attribute table (2.5KB) ---
        LEA     $00FF6100,A0                    ; $00D766 ; sprite table
        MOVE.W  #$007F,D0                       ; $00D76C ; 128 entries
.clear_display_list:
        CLR.L  (A0)+                            ; $00D770 ; 20 bytes/entry
        CLR.L  (A0)+                            ; $00D772
        CLR.L  (A0)+                            ; $00D774
        CLR.L  (A0)+                            ; $00D776
        CLR.L  (A0)+                            ; $00D778
        DBRA    D0,.clear_display_list                    ; $00D77A

; --- Initialize SH2 communication: send cmd $03 (scene ready) ---
.wait_sh2_ready:
        TST.B  COMM0_HI                        ; $00D77E ; wait for SH2 idle
        BNE.S  .wait_sh2_ready                        ; $00D784
        CLR.B  COMM1_HI                        ; $00D786 ; clear COMM1 status
        CLR.B  COMM1_LO                        ; $00D78C ; clear COMM1 data
        MOVE.B  #$03,COMM0_LO                  ; $00D792 ; cmd = $03 (scene init)
        MOVE.B  #$01,COMM0_HI                  ; $00D79A ; trigger dispatch
.wait_sh2_ack:
        TST.B  COMM0_HI                        ; $00D7A2 ; wait for SH2 to ack
        BNE.S  .wait_sh2_ack                        ; $00D7A8
        MOVE.B  #$81,(-14171).W                 ; $00D7AA ; mark scene active
        RTS                                     ; $00D7B0
