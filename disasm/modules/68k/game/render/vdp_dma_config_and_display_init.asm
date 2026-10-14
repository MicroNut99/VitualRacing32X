; ============================================================================
; vdp_dma_config_and_display_init — VDP DMA Configuration and Display Init
; ROM Range: $00D1D4-$00D3FC (552 bytes)
; Configures VDP via multiple DMA transfers. Acquires Z80 bus, sets
; VDP auto-increment, DMA length/source, and triggers transfers for
; VRAM fill, pattern data, and name tables. Loads track-specific
; data from ROM pointer tables. Handles split-screen setup with
; additional DMA for second viewport. Sets scroll registers and
; palette via VDP data port writes.
;
; Uses: D0, D1, D2, D4, D7, A0, A1, A2
; Confidence: high
; ============================================================================

vdp_dma_config_and_display_init:
; ===================================================================
; DMA #1: VRAM fill (clear entire VRAM with zeros)
; Must hold Z80 bus during DMA to prevent bus contention.
; ===================================================================
        MOVE.W  #$0100,Z80_BUSREQ                ; $00D1D4 ; request Z80 bus
.wait_z80_bus_1:
        BTST    #0,Z80_BUSREQ                    ; $00D1DC ; bus granted?
        BNE.S  .wait_z80_bus_1                        ; $00D1E4
        MOVE.W  (-14220).W,D4                   ; $00D1E6 ; VDP reg cache
        BSET    #4,D4                           ; $00D1EA ; enable DMA bit
        MOVE.W  D4,(A5)                         ; $00D1EE ; write reg 1 (DMA on)
        MOVE.W  #$8F01,(A5)                     ; $00D1F0 ; auto-inc = 1 byte
        MOVE.L  #$93FF941F,(A5)                 ; $00D1F4 ; DMA len = $1FFF words
        MOVE.W  #$9780,(A5)                     ; $00D1FA ; DMA mode = VRAM fill
        MOVE.L  #$60000082,(A5)                 ; $00D1FE ; VRAM dest = $6000
        MOVE.W  #$0000,(A6)                     ; $00D204 ; fill value = 0
.wait_dma_fill:
        MOVE.W  (A5),D7                         ; $00D208 ; read VDP status
        ANDI.W  #$0002,D7                       ; $00D20A ; DMA busy bit
        BNE.S  .wait_dma_fill                        ; $00D20E
; --- Restore auto-increment and release Z80 ---
        MOVE.W  #$8F02,(A5)                     ; $00D210 ; auto-inc = 2 (words)
        MOVE.W  (-14220).W,(A5)                 ; $00D214 ; restore VDP reg 1
        MOVE.W  #$0000,Z80_BUSREQ                ; $00D218 ; release Z80 bus

; --- Load VDP register config ---
        MOVEQ   #$07,D0                         ; $00D220 ; config preset 7
        JSR     $008814BE                       ; $00D222 ; write VDP registers

; ===================================================================
; DMA #2: Transfer pattern data to VRAM $C000 (name table A)
; Source: ROM address computed from DMA regs ($95/$96/$97).
; ===================================================================
        MOVE.W  #$0100,Z80_BUSREQ                ; $00D228 ; request Z80 bus
.wait_z80_bus_2:
        BTST    #0,Z80_BUSREQ                    ; $00D230 ; bus granted?
        BNE.S  .wait_z80_bus_2                        ; $00D238
        MOVE.W  (-14220).W,D4                   ; $00D23A ; VDP reg cache
        BSET    #4,D4                           ; $00D23E ; enable DMA
        MOVE.W  D4,(A5)                         ; $00D242 ; write reg 1
        MOVE.L  #$93409400,(A5)                 ; $00D244 ; DMA len = $0040 words
        MOVE.L  #$954096C2,(A5)                 ; $00D24A ; src addr bits 15-1
        MOVE.W  #$977F,(A5)                     ; $00D250 ; src addr bits 22-16
; --- Trigger DMA to VRAM $C000 (scroll A name table) ---
        MOVE.W  #$C000,(A5)                     ; $00D254 ; VRAM dest lo
        MOVE.W  #$0080,(-14218).W               ; $00D258 ; dest hi = $80
        MOVE.W  (-14218).W,(A5)                 ; $00D25E ; write dest hi
        MOVE.W  (-14220).W,(A5)                 ; $00D262 ; restore VDP reg
        MOVE.W  #$0000,Z80_BUSREQ                ; $00D266 ; release Z80 bus

; --- Load track-specific tile data from ROM ---
        MOVE.W  (-14176).W,D0                   ; $00D26E ; track/scene index
        lea     scene_init_vdp_dma_setup_track_param_load(pc),a0; $41FA $0188
        MOVE.L  $00(A0,D0.W),D0                 ; $00D276 ; ROM data pointer
        JSR     $008815EA                       ; $00D27A ; load + decompress

; ===================================================================
; DMA #3: Transfer name table to VRAM $4220
; For scroll plane B tile mapping.
; ===================================================================
        MOVE.W  #$0100,Z80_BUSREQ                ; $00D280 ; request Z80 bus
.wait_z80_bus_3:
        BTST    #0,Z80_BUSREQ                    ; $00D288 ; bus granted?
        BNE.S  .wait_z80_bus_3                        ; $00D290
        MOVE.W  (-14220).W,D4                   ; $00D292 ; VDP reg cache
        BSET    #4,D4                           ; $00D296 ; enable DMA
        MOVE.W  D4,(A5)                         ; $00D29A ; write reg 1
        MOVE.L  #$93009420,(A5)                 ; $00D29C ; DMA len = $2000 words
        MOVE.L  #$95009688,(A5)                 ; $00D2A2 ; src = $FF1100 >> 1
        MOVE.W  #$977F,(A5)                     ; $00D2A8 ; src hi bits
; --- Trigger DMA to VRAM $4220 (scroll B name table) ---
        MOVE.W  #$4220,(A5)                     ; $00D2AC ; VRAM dest lo
        MOVE.W  #$0080,(-14218).W               ; $00D2B0 ; dest hi = $80
        MOVE.W  (-14218).W,(A5)                 ; $00D2B6 ; write dest hi
        MOVE.W  (-14220).W,(A5)                 ; $00D2BA ; restore VDP reg
        MOVE.W  #$0000,Z80_BUSREQ                ; $00D2BE ; release Z80 bus

; --- Load split-screen track data from second table ---
        MOVE.W  (-14180).W,D1                   ; $00D2C6 ; split screen index
        LSL.W  #2,D1                            ; $00D2CA ; * 4 for longword idx
        lea     scene_init_vdp_dma_setup_track_param_load+24(pc),a0; $41FA $0146
        MOVE.L  $00(A0,D1.W),D1                 ; $00D2D0 ; ROM data pointer
        JSR     $0088155E                       ; $00D2D4 ; load track params

; --- Configure VDP scroll mode ---
        MOVE.W  #$8B00,(A5)                     ; $00D2DA ; full scroll (no line)
        MOVEQ   #$00,D0                         ; $00D2DE ; h_scroll = 0
        MOVEQ   #-$08,D1                        ; $00D2E0 ; v_scroll = -8

; --- Split-screen check and additional DMA ---
        TST.B  (-14321).W                       ; $00D2E2 ; split screen active?
        BEQ.S  .skip_split_screen                        ; $00D2E6
; --- Additional setup for split-screen mode ---
        MOVEQ   #$00,D0                         ; $00D2E8 ; h_scroll = 0
        MOVEQ   #$00,D1                         ; $00D2EA ; v_scroll = 0
        LEA     $00FF1400,A1                    ; $00D2EC ; P1 scroll table
        LEA     $00FF1000,A2                    ; $00D2F2 ; P2 scroll table
; --- Build scroll tables for both viewports ---
        JSR     $008848CA                       ; $00D2F8 ; init P1 h-scroll
        JSR     $008848CE                       ; $00D2FE ; init P1 v-scroll
        JSR     $008848D2                       ; $00D304 ; commit P1 scroll
        LEA     $00FF1200,A1                    ; $00D30A ; P2 scroll table
        JSR     $008848CA                       ; $00D310 ; init P2 h-scroll
        JSR     $008848CE                       ; $00D316 ; init P2 v-scroll
        JSR     $008848D2                       ; $00D31C ; commit P2 scroll
        MOVE.W  #$8B03,(A5)                     ; $00D322 ; line scroll mode
        bsr.w   scene_init_vdp_dma_setup_track_param_load+62; $6100 $0112 ; extra split init

; ===================================================================
; DMA #4: Transfer scroll data to VRAM $4000 (H-scroll table)
; ===================================================================
.skip_split_screen:
        MOVE.W  #$0100,Z80_BUSREQ                ; $00D32A ; request Z80 bus
.wait_z80_bus_4:
        BTST    #0,Z80_BUSREQ                    ; $00D332 ; bus granted?
        BNE.S  .wait_z80_bus_4                        ; $00D33A
        MOVE.W  (-14220).W,D4                   ; $00D33C ; VDP reg cache
        BSET    #4,D4                           ; $00D340 ; enable DMA
        MOVE.W  D4,(A5)                         ; $00D344 ; write reg 1
        MOVE.L  #$9300940E,(A5)                 ; $00D346 ; DMA len = $000E words
        MOVE.L  #$95009688,(A5)                 ; $00D34C ; src = $FF1100 >> 1
        MOVE.W  #$977F,(A5)                     ; $00D352 ; src hi bits
; --- Trigger DMA to VRAM $4000 (H-scroll table) ---
        MOVE.W  #$4000,(A5)                     ; $00D356 ; VRAM dest lo
        MOVE.W  #$0083,(-14218).W               ; $00D35A ; dest hi = $83
        MOVE.W  (-14218).W,(A5)                 ; $00D360 ; write dest hi
        MOVE.W  (-14220).W,(A5)                 ; $00D364 ; restore VDP reg
        MOVE.W  #$0000,Z80_BUSREQ                ; $00D368 ; release Z80 bus

; --- Optional: split-screen row-by-row tile setup ---
        BTST    #3,(-14322).W                   ; $00D370 ; split row mode?
        BEQ.S  .set_scroll_regs                        ; $00D376
        MOVEQ   #$00,D1                         ; $00D378 ; start row = 0
        MOVE.L  #$000000B0,D2                   ; $00D37A ; row stride = 176B
        MOVEQ   #$1B,D7                         ; $00D380 ; 28 rows
        LEA     $00FF1A50,A1                    ; $00D382 ; row tile buffer
.split_row_loop:
        JSR     $0088485E                       ; $00D388 ; build tile row
        ADDA.L  D2,A1                           ; $00D38E ; advance to next row
        DBRA    D7,.split_row_loop                    ; $00D390

; ===================================================================
; DMA #5: Transfer split row tiles to VRAM $6000 (window plane)
; ===================================================================
        MOVE.W  #$0100,Z80_BUSREQ                ; $00D394 ; request Z80 bus
.wait_z80_bus_5:
        BTST    #0,Z80_BUSREQ                    ; $00D39C ; bus granted?
        BNE.S  .wait_z80_bus_5                        ; $00D3A4
        MOVE.W  (-14220).W,D4                   ; $00D3A6 ; VDP reg cache
        BSET    #4,D4                           ; $00D3AA ; enable DMA
        MOVE.W  D4,(A5)                         ; $00D3AE ; write reg 1
        MOVE.L  #$9300940E,(A5)                 ; $00D3B0 ; DMA len = $000E words
        MOVE.L  #$9500968D,(A5)                 ; $00D3B6 ; src addr
        MOVE.W  #$977F,(A5)                     ; $00D3BC ; src hi bits
; --- Trigger DMA to VRAM $6000 (window/overlay) ---
        MOVE.W  #$6000,(A5)                     ; $00D3C0 ; VRAM dest lo
        MOVE.W  #$0082,(-14218).W               ; $00D3C4 ; dest hi = $82
        MOVE.W  (-14218).W,(A5)                 ; $00D3CA ; write dest hi
        MOVE.W  (-14220).W,(A5)                 ; $00D3CE ; restore VDP reg
        MOVE.W  #$0000,Z80_BUSREQ                ; $00D3D2 ; release Z80 bus

; ===================================================================
; Set scroll registers and write initial values to VDP
; ===================================================================
.set_scroll_regs:
        MOVE.W  #$FFFC,(-14208).W               ; $00D3DA ; h_scroll = -4
        MOVE.W  D1,(-14206).W                   ; $00D3E0 ; v_scroll from above
        MOVE.W  D0,(-32768).W                   ; $00D3E4 ; scroll buf A
        MOVE.W  D0,(-32766).W                   ; $00D3E8 ; scroll buf B
; --- Write scroll values to VDP via data port ---
        MOVE.L  #$40000010,(A5)                 ; $00D3EC ; VSRAM write addr $0000
        MOVE.W  (-14208).W,(A6)                 ; $00D3F2 ; write h_scroll
        MOVE.W  (-14206).W,(A6)                 ; $00D3F6 ; write v_scroll
        RTS                                     ; $00D3FA
