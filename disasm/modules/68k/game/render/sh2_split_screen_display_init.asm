; ============================================================================
; sh2_split_screen_display_init — SH2 Split-Screen Display Initialization
; ROM Range: $00E5CE-$00E88C (702 bytes)
; Scene initialization for split-screen modes. Three entry points
; configure single-screen, dual-screen, and replay modes by setting
; palette indices and split-screen flags. Shared body clears VDP,
; CRAM, and framebuffer; loads SH2 graphics commands for tile layout;
; transfers compressed palette/tile data via sh2_send_cmd_wait;
; configures viewport parameters and 32X VDP mode. Nearly identical
; to sh2_display_and_palette_init but handles additional split-screen tile regions.
;
; Uses: D0, D1, D2, D3, D4, A0, A1, A5
; Calls: $00E1BC (sh2_palette_load), $00E22C (sh2_graphics_cmd),
;        $00E2F0 (sh2_load_data), $00E316 (sh2_send_cmd_wait)
; Confidence: high
; ============================================================================

; --- Entry point 1: Single-screen mode ---
sh2_split_screen_display_init:
        CLR.B  (-24545).W                       ; $00E5CE ; clear split flag
        MOVE.B  (-343).W,(-24547).W             ; $00E5D2 ; palette from ROM
        MOVE.B  (-335).W,(-24551).W             ; $00E5D8 ; main palette idx
        BCLR    #7,(-600).W                     ; $00E5DE ; clear overlay mode
        BRA.S  .shared_init                      ; $00E5E4

; --- Entry point 2: Dual-screen mode ---
        CLR.B  (-24545).W                       ; $00E5E6 ; clear split flag
        MOVE.B  (-343).W,(-24547).W             ; $00E5EA ; palette from ROM
        MOVE.B  (-335).W,(-24551).W             ; $00E5F0 ; main palette idx
        BSET    #7,(-600).W                     ; $00E5F6 ; enable overlay mode
        BRA.S  .shared_init                      ; $00E5FC

; --- Entry point 3: Replay/multi mode ---
        MOVE.B  #$01,(-24545).W                 ; $00E5FE ; split flag = 1
        MOVE.B  (-342).W,(-24547).W             ; $00E604 ; alt palette from ROM
        BCLR    #7,(-600).W                     ; $00E60A ; clear overlay mode
        MOVE.B  (-334).W,(-24551).W             ; $00E610 ; replay palette idx

; --- Shared initialization body ---
.shared_init:
        MOVE.W  #$002C,$00FF0008                ; $00E616 ; display timing
        MOVE.W  #$002C,(-14214).W               ; $00E61E ; timing copy
        BCLR    #6,(-14219).W                   ; $00E624 ; clear interlace
        MOVE.W  (-14220).W,(A5)                 ; $00E62A ; write VDP reg cache
; --- Configure 32X MARS ---
        MOVE.W  #$0083,MARS_SYS_INTCTL                ; $00E62E ; enable MARS ints
        ANDI.B  #$FC,MARS_VDP_MODE+1                  ; $00E636 ; clear mode bits
        JSR     $008826C8                       ; $00E63E ; clear MARS framebuf
        MOVE.L  #$000A0907,D0                   ; $00E644 ; VDP config params
        JSR     $008814BE                       ; $00E64A ; write VDP registers
        MOVE.B  #$01,(-14323).W                 ; $00E650 ; mark init active

; --- Clear work RAM buffers ---
        MOVEQ   #$00,D0                         ; $00E656
        LEA     (-31616).W,A0                   ; $00E658 ; score buffer
        MOVEQ   #$1F,D1                         ; $00E65C ; 32 longs = 128B
.clear_score_loop:
        MOVE.L  D0,(A0)+                        ; $00E65E
        DBRA    D1,.clear_score_loop                    ; $00E660
        LEA     $00FF7B80,A0                    ; $00E664 ; display list buf
        MOVEQ   #$7F,D1                         ; $00E66A ; 128 longs = 512B
.clear_display_loop:
        MOVE.L  D0,(A0)+                        ; $00E66C
        DBRA    D1,.clear_display_loop                    ; $00E66E

; --- Clear VDP VRAM ---
        MOVE.L  #$60000002,(A5)                 ; $00E672 ; VRAM write addr $6000
        MOVE.W  #$17FF,D1                       ; $00E678 ; 6144 longs = 24KB
.clear_vram_loop:
        MOVE.L  D0,(A6)                         ; $00E67C ; write to VDP data
        DBRA    D1,.clear_vram_loop                    ; $00E67E

        JSR     $008849AA                       ; $00E682 ; wait VDP ready
; --- Clear rendering state ---
        CLR.W  (-14208).W                       ; $00E688 ; h_scroll
        CLR.W  (-14206).W                       ; $00E68C ; v_scroll
        CLR.W  (-32768).W                       ; $00E690 ; scroll buf A
        CLR.W  (-32766).W                       ; $00E694 ; scroll buf B
        CLR.W  (-24558).W                       ; $00E698 ; panel config
        CLR.B  (-24552).W                       ; $00E69C ; palette state
        JSR     $008849AA                       ; $00E6A0 ; wait VDP ready

; --- Set up rendering configuration ---
        MOVE.L  #$008BB4FC,(-13972).W           ; $00E6A6 ; ROM pointer table
        MOVE.B  #$01,(-14327).W                 ; $00E6AE ; enable flag A
        MOVE.B  #$01,(-14326).W                 ; $00E6B4 ; enable flag B
        BSET    #6,(-14322).W                   ; $00E6BA ; set render bit 6
        MOVE.B  #$01,(-14334).W                 ; $00E6C0 ; DMA enable
        MOVE.W  #$0001,(-24544).W               ; $00E6C6 ; active panel count

; --- Clear tile work buffer (4KB) ---
        LEA     $00FF1000,A0                    ; $00E6CC ; tile work buffer
        MOVE.W  #$037F,D0                       ; $00E6D2 ; 896 longs = 3.5KB
.clear_tilemap_loop:
        CLR.L  (A0)+                            ; $00E6D6
        DBRA    D0,.clear_tilemap_loop                    ; $00E6D8

; --- SH2 graphics commands for split-screen tile layout ---
; Panel 1 (P1 viewport: top portion)
        MOVE.W  #$0001,D0                       ; $00E6DC ; panel ID = 1
        MOVE.W  #$0001,D1                       ; $00E6E0 ; start col = 1
        MOVE.W  #$0001,D2                       ; $00E6E4 ; start row = 1
        MOVE.W  #$0026,D3                       ; $00E6E8 ; width = 38 tiles
        MOVE.W  #$0014,D4                       ; $00E6EC ; height = 20 tiles
        LEA     $00FF1000,A0                    ; $00E6F0
        jsr     sh2_graphics_cmd(pc)    ; $4EBA $FB34
; Panel 2 (P2 viewport: bottom portion)
        MOVE.W  #$0002,D0                       ; $00E6FA ; panel ID = 2
        MOVE.W  #$0001,D1                       ; $00E6FE ; start col = 1
        MOVE.W  #$0016,D2                       ; $00E702 ; start row = 22
        MOVE.W  #$0026,D3                       ; $00E706 ; width = 38 tiles
        MOVE.W  #$0005,D4                       ; $00E70A ; height = 5 tiles
        LEA     $00FF1000,A0                    ; $00E70E
        jsr     sh2_graphics_cmd(pc)    ; $4EBA $FB16
        LEA     $00FF1000,A0                    ; $00E718
        jsr     sh2_load_data(pc)       ; $4EBA $FBD0

; --- Load SH2 palette ---
        DC.W    $4EBA,$FA98         ; JSR     $00E1BC(PC); $00E722 ; sh2_palette_load

; --- Copy palette with priority bit ---
        BCLR    #7,MARS_VDP_MODE+1                    ; $00E726 ; clear bitmap mode
        LEA     $00FF6E00,A0                    ; $00E72E ; CRAM buffer base
        LEA     $008BA220,A1                    ; $00E734 ; palette ptr table
        MOVEA.L (A1),A1                         ; $00E73A ; deref ptr
        MOVE.W  #$007F,D0                       ; $00E73C ; 128 colors
.copy_palette_loop:
        MOVE.W  (A1)+,(A0)+                     ; $00E740
        DBRA    D0,.copy_palette_loop                    ; $00E742
; --- Overlay palette with priority bit ---
        LEA     $00FF6E00,A0                    ; $00E746 ; CRAM base
        ADDA.L  #$00000160,A0                   ; $00E74C ; +352 = overlay slot
        LEA     $0088E88C,A1                    ; $00E752 ; ROM palette source
        MOVE.W  #$003F,D0                       ; $00E758 ; 64 colors
.copy_overlay_palette_loop:
        MOVE.W  (A1)+,D1                        ; $00E75C
        BSET    #15,D1                          ; $00E75E ; set priority bit
        MOVE.W  D1,(A0)+                        ; $00E762
        DBRA    D0,.copy_overlay_palette_loop                    ; $00E764

; --- Transfer compressed tile data to SH2 SDRAM ---
; 4 data blocks for split-screen tile regions
        LEA     $000E9680,A0                    ; $00E768 ; block 1: shared tiles
        MOVEA.L #$06038000,A1                   ; $00E76E ; SH2 SDRAM dest
        DC.W    $4EBA,$FBA0         ; JSR     $00E316(PC); $00E774 ; sh2_send_cmd_wait
        LEA     $000E9450,A0                    ; $00E778 ; block 2: name table
        MOVEA.L #$0603B600,A1                   ; $00E77E ; SH2 SDRAM dest
        DC.W    $4EBA,$FB90         ; JSR     $00E316(PC); $00E784 ; sh2_send_cmd_wait
        LEA     $000E90A0,A0                    ; $00E788 ; block 3: overlay
        MOVEA.L #$0603D100,A1                   ; $00E78E ; SH2 SDRAM dest
        DC.W    $4EBA,$FB80         ; JSR     $00E316(PC); $00E794 ; sh2_send_cmd_wait
        LEA     $000E9240,A0                    ; $00E798 ; block 4: panel data
        MOVEA.L #$0603D800,A1                   ; $00E79E ; SH2 SDRAM dest
        DC.W    $4EBA,$FB70         ; JSR     $00E316(PC); $00E7A4 ; sh2_send_cmd_wait

; --- Initialize viewport parameters ---
        MOVE.B  (-24551).W,(-24546).W           ; $00E7A8 ; P1 palette -> config
        CLR.B  (-24550).W                       ; $00E7AE ; clear P2 X offset
; --- Viewport parameter table at $FF2000 (9 words) ---
        MOVE.W  #$0080,$00FF2000                ; $00E7B2 ; P1 X center = 128
        MOVE.W  #$FF80,$00FF2002                ; $00E7BA ; P1 Y center = -128
        MOVE.W  #$003C,$00FF2004                ; $00E7C2 ; P1 depth = 60
        MOVE.W  #$00BC,$00FF2006                ; $00E7CA ; P2 X center = 188
        MOVE.W  #$FF60,$00FF2008                ; $00E7D2 ; P2 Y center = -160
        MOVE.W  #$0044,$00FF200A                ; $00E7DA ; P2 depth = 68
        MOVE.W  #$0080,$00FF200C                ; $00E7E2 ; shared X = 128
        MOVE.W  #$FF80,$00FF200E                ; $00E7EA ; shared Y = -128
        MOVE.W  #$003C,$00FF2010                ; $00E7F2 ; shared depth = 60

; --- Final 32X VDP configuration ---
        JSR     $0088204A                       ; $00E7FA ; CRAM DMA transfer
        ANDI.B  #$FC,MARS_VDP_MODE+1                  ; $00E800 ; clear mode bits
        ORI.B  #$01,MARS_VDP_MODE+1                   ; $00E808 ; 256-color mode
        MOVE.W  #$8083,MARS_SYS_INTCTL                ; $00E810 ; enable V+H INT
        BSET    #6,(-14219).W                   ; $00E818 ; set interlace
        MOVE.W  (-14220).W,(A5)                 ; $00E81E ; update VDP regs
        MOVE.W  #$0020,$00FF0008                ; $00E822 ; display timing
        JSR     $00884998                       ; $00E82A ; init scroll tables
        MOVE.W  #$0000,(-14210).W               ; $00E830 ; state counter = 0
        MOVE.L  #$0088E90C,$00FF0002            ; $00E836 ; dispatch table ptr
        MOVE.B  #$81,(-14171).W                 ; $00E840 ; mark scene active
        MOVE.B  #$00,$00FF60D4                  ; $00E846 ; overlay off

; --- Clear sprite attribute table (2.5KB) ---
        LEA     $00FF6100,A0                    ; $00E84E ; sprite table
        MOVE.W  #$007F,D0                       ; $00E854 ; 128 entries
.clear_sprite_table_loop:
        CLR.L  (A0)+                            ; $00E858 ; 20 bytes/entry
        CLR.L  (A0)+                            ; $00E85A
        CLR.L  (A0)+                            ; $00E85C
        CLR.L  (A0)+                            ; $00E85E
        CLR.L  (A0)+                            ; $00E860
        DBRA    D0,.clear_sprite_table_loop                    ; $00E862

; --- Signal SH2: scene init command ---
.wait_comm_ready:
        TST.B  COMM0_HI                        ; $00E866 ; wait SH2 idle
        BNE.S  .wait_comm_ready                        ; $00E86C
        CLR.B  COMM1_HI                        ; $00E86E ; clear COMM1 status
        CLR.B  COMM1_LO                        ; $00E874 ; clear COMM1 data
        MOVE.B  #$03,COMM0_LO                  ; $00E87A ; cmd $03 = scene init
        MOVE.B  #$01,COMM0_HI                  ; $00E882 ; trigger dispatch
        RTS                                     ; $00E88A
