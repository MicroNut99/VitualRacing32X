; ============================================================================
; sh2_three_panel_display_init — SH2 Three-Panel Display Initialization
; ROM Range: $00F130-$00F39C (620 bytes)
; Data prefix (12 bytes: 3 longword entry point pointers). Scene
; initialization for three-panel display mode. Configures 32X VDP,
; clears framebuffer/CRAM, loads palette and tile graphics via
; sh2_graphics_cmd (3 tile regions). Transfers 8 compressed data
; blocks to SH2 memory via sh2_send_cmd_wait. Initializes palette
; selection and panel configuration parameters.
;
; Uses: D0, D1, D2, D3, D4, A0, A1, A5
; Calls: $00E1BC (sh2_palette_load), $00E22C (sh2_graphics_cmd),
;        $00E2F0 (sh2_load_data), $00E316 (sh2_send_cmd_wait)
; Confidence: high
; ============================================================================

; --- Data prefix: 3 longword entry point pointers ---
; Disassembler shows as MOVE.L instructions but these are data.
sh2_three_panel_display_init:
        MOVE.L  -$7E66(A0),D1                   ; $00F130 ; data: ptr 0
        MOVE.L  -$7DA4(A0),D1                   ; $00F134 ; data: ptr 1
        MOVE.L  -$7CE2(A0),D1                   ; $00F138 ; data: ptr 2

; --- Initialization begins ---
        BCLR    #7,(-600).W                     ; $00F13C ; clear overlay mode
        MOVE.W  #$002C,$00FF0008                ; $00F142 ; display timing
        MOVE.W  #$002C,(-14214).W               ; $00F14A ; timing copy
        BCLR    #6,(-14219).W                   ; $00F150 ; clear interlace
        MOVE.W  (-14220).W,(A5)                 ; $00F156 ; write VDP reg cache
; --- Configure 32X MARS ---
        MOVE.W  #$0083,MARS_SYS_INTCTL                ; $00F15A ; enable MARS ints
        ANDI.B  #$FC,MARS_VDP_MODE+1                  ; $00F162 ; clear mode bits
        JSR     $008826C8                       ; $00F16A ; clear MARS framebuf
        MOVE.L  #$000A0907,D0                   ; $00F170 ; VDP config params
        JSR     $008814BE                       ; $00F176 ; write VDP registers
        MOVE.B  #$01,(-14323).W                 ; $00F17C ; mark init active

; --- Clear work RAM buffers ---
        MOVEQ   #$00,D0                         ; $00F182
        LEA     (-31616).W,A0                   ; $00F184 ; score buffer
        MOVEQ   #$1F,D1                         ; $00F188 ; 32 longs = 128B
.clear_score_loop:
        MOVE.L  D0,(A0)+                        ; $00F18A
        DBRA    D1,.clear_score_loop                    ; $00F18C
        LEA     $00FF7B80,A0                    ; $00F190 ; display list buf
        MOVEQ   #$7F,D1                         ; $00F196 ; 128 longs = 512B
.clear_display_loop:
        MOVE.L  D0,(A0)+                        ; $00F198
        DBRA    D1,.clear_display_loop                    ; $00F19A

; --- Clear VDP VRAM ---
        MOVE.L  #$60000002,(A5)                 ; $00F19E ; VRAM write addr $6000
        MOVE.W  #$17FF,D1                       ; $00F1A4 ; 6144 longs = 24KB
.clear_vram_loop:
        MOVE.L  D0,(A6)                         ; $00F1A8 ; write to VDP data
        DBRA    D1,.clear_vram_loop                    ; $00F1AA

        JSR     $008849AA                       ; $00F1AE ; wait VDP ready
; --- Clear rendering state ---
        CLR.W  (-14208).W                       ; $00F1B4 ; h_scroll
        CLR.W  (-14206).W                       ; $00F1B8 ; v_scroll
        CLR.W  (-32768).W                       ; $00F1BC ; scroll buf A
        CLR.W  (-32766).W                       ; $00F1C0 ; scroll buf B
        CLR.W  (-24558).W                       ; $00F1C4 ; panel config
        CLR.B  (-24552).W                       ; $00F1C8 ; palette state
        JSR     $008849AA                       ; $00F1CC ; wait VDP ready

; --- Set up rendering configuration ---
        MOVE.L  #$008BB4FC,(-13972).W           ; $00F1D2 ; ROM pointer table
        MOVE.B  #$01,(-14327).W                 ; $00F1DA ; enable flag A
        MOVE.B  #$01,(-14326).W                 ; $00F1E0 ; enable flag B
        BSET    #6,(-14322).W                   ; $00F1E6 ; set render bit 6
        MOVE.B  #$01,(-14334).W                 ; $00F1EC ; DMA enable
        MOVE.W  #$0001,(-24540).W               ; $00F1F2 ; active panel = 1

; --- Clear tile work buffer (4KB) ---
        LEA     $00FF1000,A0                    ; $00F1F8 ; tile work buffer
        MOVE.W  #$037F,D0                       ; $00F1FE ; 896 longs = 3.5KB
.clear_tilemap_loop:
        CLR.L  (A0)+                            ; $00F202
        DBRA    D0,.clear_tilemap_loop                    ; $00F204

; --- SH2 graphics commands for 3-panel tile layout ---
; Panel 1 (top strip)
        MOVE.W  #$0001,D0                       ; $00F208 ; panel ID = 1
        MOVE.W  #$0001,D1                       ; $00F20C ; start col = 1
        MOVE.W  #$0001,D2                       ; $00F210 ; start row = 1
        MOVE.W  #$0026,D3                       ; $00F214 ; width = 38 tiles
        MOVE.W  #$0009,D4                       ; $00F218 ; height = 9 tiles
        LEA     $00FF1000,A0                    ; $00F21C
        jsr     sh2_graphics_cmd(pc)    ; $4EBA $F008
; Panel 2 (left column)
        MOVE.W  #$0002,D0                       ; $00F226 ; panel ID = 2
        MOVE.W  #$0001,D1                       ; $00F22A ; start col = 1
        MOVE.W  #$000B,D2                       ; $00F22E ; start row = 11
        MOVE.W  #$0013,D3                       ; $00F232 ; width = 19 tiles
        MOVE.W  #$0010,D4                       ; $00F236 ; height = 16 tiles
        LEA     $00FF1000,A0                    ; $00F23A
        jsr     sh2_graphics_cmd(pc)    ; $4EBA $EFEA
; Panel 3 (right column)
        MOVE.W  #$0003,D0                       ; $00F244 ; panel ID = 3
        MOVE.W  #$0014,D1                       ; $00F248 ; start col = 20
        MOVE.W  #$000B,D2                       ; $00F24C ; start row = 11
        MOVE.W  #$0013,D3                       ; $00F250 ; width = 19 tiles
        MOVE.W  #$0010,D4                       ; $00F254 ; height = 16 tiles
        LEA     $00FF1000,A0                    ; $00F258
        jsr     sh2_graphics_cmd(pc)    ; $4EBA $EFCC
        LEA     $00FF1000,A0                    ; $00F262
        jsr     sh2_load_data(pc)       ; $4EBA $F086

; --- Load SH2 palette ---
        DC.W    $4EBA,$EF4E         ; JSR     $00E1BC(PC); $00F26C ; sh2_palette_load

; --- Copy overlay palette with priority bit ---
        BCLR    #7,MARS_VDP_MODE+1                    ; $00F270 ; clear bitmap mode
        LEA     $00FF6E00,A0                    ; $00F278 ; CRAM buffer base
        ADDA.L  #$00000160,A0                   ; $00F27E ; +352 = overlay slot
        LEA     $0088F39C,A1                    ; $00F284 ; ROM palette source
        MOVE.W  #$003F,D0                       ; $00F28A ; 64 colors
.copy_palette_loop:
        MOVE.W  (A1)+,D1                        ; $00F28E
        BSET    #15,D1                          ; $00F290 ; set priority bit
        MOVE.W  D1,(A0)+                        ; $00F294
        DBRA    D0,.copy_palette_loop                    ; $00F296

; --- Transfer 8 compressed data blocks to SH2 SDRAM ---
        LEA     $000E9680,A0                    ; $00F29A ; block 1: shared tiles
        MOVEA.L #$06038000,A1                   ; $00F2A0 ; SH2 dest
        DC.W    $4EBA,$F06E         ; JSR     $00E316(PC); $00F2A6 ; sh2_send_cmd_wait
        LEA     $000E9F60,A0                    ; $00F2AA ; block 2: panel 1 tiles
        MOVEA.L #$0603B600,A1                   ; $00F2B0 ; SH2 dest
        DC.W    $4EBA,$F05E         ; JSR     $00E316(PC); $00F2B6 ; sh2_send_cmd_wait
        LEA     $000EA080,A0                    ; $00F2BA ; block 3: panel 2 tiles
        MOVEA.L #$0603BC00,A1                   ; $00F2C0 ; SH2 dest
        DC.W    $4EBA,$F04E         ; JSR     $00E316(PC); $00F2C6 ; sh2_send_cmd_wait
        LEA     $000EA240,A0                    ; $00F2CA ; block 4: panel 3 tiles
        MOVEA.L #$0603C400,A1                   ; $00F2D0 ; SH2 dest
        DC.W    $4EBA,$F03E         ; JSR     $00E316(PC); $00F2D6 ; sh2_send_cmd_wait
        LEA     $000EA340,A0                    ; $00F2DA ; block 5: panel borders
        MOVEA.L #$0603C880,A1                   ; $00F2E0 ; SH2 dest
        DC.W    $4EBA,$F02E         ; JSR     $00E316(PC); $00F2E6 ; sh2_send_cmd_wait
        LEA     $000E90A0,A0                    ; $00F2EA ; block 6: overlay data
        MOVEA.L #$0603D780,A1                   ; $00F2F0 ; SH2 dest
        DC.W    $4EBA,$F01E         ; JSR     $00E316(PC); $00F2F6 ; sh2_send_cmd_wait
        LEA     $000EA5F0,A0                    ; $00F2FA ; block 7: extra tiles
        MOVEA.L #$0603DE80,A1                   ; $00F300 ; SH2 dest
        DC.W    $4EBA,$F00E         ; JSR     $00E316(PC); $00F306 ; sh2_send_cmd_wait
        LEA     $000EA710,A0                    ; $00F30A ; block 8: final data
        MOVEA.L #$0603F200,A1                   ; $00F310 ; SH2 dest
        DC.W    $4EBA,$EFFE         ; JSR     $00E316(PC); $00F316 ; sh2_send_cmd_wait

; --- Initialize panel configuration parameters ---
        MOVE.B  (-24545).W,(-24551).W           ; $00F31A ; copy split palette
        CLR.B  (-24549).W                       ; $00F320 ; clear panel mode
        MOVE.B  (-333).W,(-24551).W             ; $00F324 ; main palette from ROM
        MOVE.B  (-336).W,(-24550).W             ; $00F32A ; P2 palette from ROM
        MOVE.B  #$01,(-24548).W                 ; $00F330 ; P2 panel mode = 1
        MOVE.B  (-337).W,(-24544).W             ; $00F336 ; P1 aux palette
        MOVE.B  (-336).W,(-24542).W             ; $00F33C ; P2 aux palette
        MOVE.B  (-339).W,(-24543).W             ; $00F342 ; P1 stats palette
        MOVE.B  (-338).W,(-24541).W             ; $00F348 ; P2 stats palette

; --- Final 32X VDP configuration ---
        JSR     $0088204A                       ; $00F34E ; CRAM DMA transfer
        ANDI.B  #$FC,MARS_VDP_MODE+1                  ; $00F354 ; clear mode bits
        ORI.B  #$01,MARS_VDP_MODE+1                   ; $00F35C ; 256-color mode
        MOVE.W  #$8083,MARS_SYS_INTCTL                ; $00F364 ; enable V+H INT
        BSET    #6,(-14219).W                   ; $00F36C ; set interlace
        MOVE.W  (-14220).W,(A5)                 ; $00F372 ; update VDP regs
        MOVE.W  #$0020,$00FF0008                ; $00F376 ; display timing
        JSR     $00884998                       ; $00F37E ; init scroll tables
        MOVE.W  #$0000,(-14210).W               ; $00F384 ; state counter = 0
        MOVE.L  #$0088F41C,$00FF0002            ; $00F38A ; dispatch table ptr
        MOVE.B  #$81,(-14171).W                 ; $00F394 ; mark scene active
        RTS                                     ; $00F39A
