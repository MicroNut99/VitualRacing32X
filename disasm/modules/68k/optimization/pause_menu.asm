; ============================================================================
; VirtuaRacing32X: pause menu and timing line (68000, Genesis VDP plane A)
; ============================================================================
; Lives in the free ROM after object_table_sprite_param_update (code_1c200).
; Everything here is reached through absolute addresses ($880000 + label),
; because the hooks are more than 32 KB away.
;
; Hooks (each one line in the game code, marked "VR32X"):
;   - main loop template ($000F92, copied to $FF0000): the STOP / wait for
;     V-INT is replaced by "jsr pm_loop_wait" (68000 busy time, timing line)
;   - vint_handler ($001684): first instruction "jmp pm_vint" (frame and
;     frame-buffer swap counting)
;   - pause sub-state table ($0057A4): entry [08] -> pm_pause_tick (the menu),
;     entry [10] -> pm_quit_stage (QUIT or RESTART after the game's own
;     quit teardown)
;
; Drawing: plane A (name table $A000, 128 cells wide), unused in 1-player
; races. Font: 64 tiles at VRAM $4400 (tile $220), in the free VRAM after
; the track tiles. Box tile: $260. Palette line 2 (unused in races):
; 1 = white, 3 = black (shadow), 4 = dark box; line 3 entries 1/3/4 for the
; selected line (yellow). Written into the CRAM shadow at $FF8480, which the
; V-INT handlers DMA to CRAM.
;
; Work RAM $FF0800-$FF08FF: zero all through attract, menus, a race and its
; results in a RAM survey (the game keeps its records at $FFF700-$FFF8FF)
; ============================================================================

PM_BASE         equ     $00FF0800
pm_magic        equ     PM_BASE+$00     ; .w $B532 once initialised
pm_open         equ     PM_BASE+$02     ; .b menu on screen
pm_sel          equ     PM_BASE+$03     ; .b selected line
pm_restart      equ     PM_BASE+$04     ; .b 1: the quit sequence restarts the race
pm_timing       equ     PM_BASE+$06     ; .b 1: timing line on
pm_dirty        equ     PM_BASE+$07     ; .b new numbers to draw
pm_fs_last      equ     PM_BASE+$08     ; .b last frame-buffer select bit seen
pm_drawn        equ     PM_BASE+$09     ; .b timing line is on plane A
pm_swaps        equ     PM_BASE+$0A     ; .w frame-buffer swaps this second
pm_ticks        equ     PM_BASE+$0C     ; .w V-INTs this second
pm_lag          equ     PM_BASE+$0E     ; .w V-INTs this second with the 68K busy
pm_busy         equ     PM_BASE+$10     ; .l 68K busy lines this second
pm_abs          equ     PM_BASE+$14     ; .l all V-INTs since start
pm_t_wake       equ     PM_BASE+$18     ; .l line time when the 68K woke up
pm_fps          equ     PM_BASE+$1C     ; .w shown: swaps per second
pm_cpu          equ     PM_BASE+$1E     ; .w shown: 68K busy, percent
pm_lagshow      equ     PM_BASE+$20     ; .w shown: lag frames per second

PM_VDP_DATA        equ     $C00000
PM_VDP_CTRL        equ     $C00004
PM_VDP_HV          equ     $C00008
PM_MARS_FS         equ     $A1518B         ; 32X frame buffer select (bit 0)
PM_COMM0_HI        equ     $A15120
PM_COMM1_LO        equ     $A15123

PM_TILE         equ     $0220           ; first font tile (ASCII $20)
PM_BOX          equ     $0260           ; solid dark tile
PM_ATTR         equ     $C000           ; priority + palette line 2
PM_ATTR_SEL     equ     $E000           ; priority + palette line 3
PM_ROWS         equ     $A000           ; plane A name table
PM_FB             equ   $840000         ; 32X frame buffer as the 68000 sees it (FM = 0)
PM_MARS_FBC       equ   $A1518B         ; frame buffer control, bit 0 = FS (shown)
PM_FB_LINE        equ   210             ; timing line: the black strip under the 3D view
PM_FB_CHARS       equ   20
PM_FB_X           equ   (320-PM_FB_CHARS*8)/2
pm_fbpend         equ   PM_BASE+$23     ; .b bit 0/1: frame buffer 0/1 still to get the text
PM_MARS_MODE    equ     $A15181         ; 32X bitmap mode, bit 7 = PRI
PM_MARS_ADAPT   equ     $A15100         ; adapter control, bit 7 = FM (1: SH2 owns the 32X VDP)

PM_MENU_ROW     equ     7
PM_MENU_COL     equ     9
PM_MENU_W       equ     22
PM_MENU_H       equ     12
PM_ITEMS        equ     4

; VRAM write address command for VRAM address \1 into d7
pm_vram_cmd     macro
        move.l  #((((\1)&$3FFF)<<16)|$40000000|((\1)>>14)),d7
        endm

; ----------------------------------------------------------------------------
; pm_init: first use after power-on (work RAM is not cleared for us)
; ----------------------------------------------------------------------------
pm_init:
        cmpi.w  #$B532,(pm_magic).l
        beq.s   .done
        movem.l d0/a0,-(sp)
        lea     (PM_BASE).l,a0
        moveq   #$40/4-1,d0
.clr:   clr.l   (a0)+
        dbra    d0,.clr
        move.w  #$B532,(pm_magic).l
        movem.l (sp)+,d0/a0
.done:  rts

; ----------------------------------------------------------------------------
; pm_vint: every V-INT, before the game's handler
; ----------------------------------------------------------------------------
pm_vint:
        movem.l d0-d1,-(sp)
        bsr.s   pm_init
        addq.l  #1,(pm_abs).l
        addq.w  #1,(pm_ticks).l
        tst.w   ($FFFFC87A).w                   ; 0: main loop still busy
        bne.s   .worked
        addq.w  #1,(pm_lag).l
.worked:
        move.b  (PM_MARS_FS).l,d0                  ; frame buffer shown
        andi.b  #1,d0
        cmp.b   (pm_fs_last).l,d0
        beq.s   .same
        move.b  d0,(pm_fs_last).l
        addq.w  #1,(pm_swaps).l
.same:
        cmpi.w  #60,(pm_ticks).l                ; one second
        blo.s   .out
        move.w  (pm_swaps).l,(pm_fps).l
        move.w  (pm_lag).l,(pm_lagshow).l
        move.l  (pm_busy).l,d0                  ; busy lines * 100 / (60 * 262)
        mulu.w  #100,d0                         ; (fits: < 15720 lines)
        divu.w  #60*262,d0
        cmpi.w  #100,d0
        bls.s   .pct
        moveq   #100,d0
.pct:   move.w  d0,(pm_cpu).l
        clr.w   (pm_swaps).l
        clr.w   (pm_ticks).l
        clr.w   (pm_lag).l
        clr.l   (pm_busy).l
        st      (pm_dirty).l
.out:
        movem.l (sp)+,d0-d1
        tst.w   ($FFFFC87A).w                   ; the game's own first two
        beq.s   .rte                            ; instructions
        jmp     ($00880000+vint_handler+6).l
.rte:   rte

; line time: V-INTs * 262 + lines since the start of vblank (d0)
pm_line_time:
        move.l  (pm_abs).l,d0
        mulu.w  #262,d0
        moveq   #0,d1
        move.b  (PM_VDP_HV).l,d1                   ; V counter
        subi.w  #224,d1
        bpl.s   .add
        addi.w  #262,d1
.add:   add.l   d1,d0
        rts

; ----------------------------------------------------------------------------
; pm_loop_wait: replaces "STOP #$2300 / wait for V-INT" in the main loop
; ----------------------------------------------------------------------------
pm_loop_wait:
        movem.l d0-d7/a0-a2,-(sp)
        bsr     pm_init
        bsr.s   pm_line_time                    ; work done: count its lines
        sub.l   (pm_t_wake).l,d0
        bmi.s   .nocount
        cmpi.l  #262*8,d0                       ; ignore nonsense (first frame)
        bhi.s   .nocount
        add.l   d0,(pm_busy).l
.nocount:
        bsr     pm_timing_update
        movem.l (sp)+,d0-d7/a0-a2
.wait:  stop    #$2300
        tst.w   ($FFFFC87A).w
        bne.s   .wait
        movem.l d0-d1,-(sp)
        bsr.s   pm_line_time
        move.l  d0,(pm_t_wake).l
        movem.l (sp)+,d0-d1
        rts

; racing: main loop handler is one of the race dispatchers
pm_in_race:
        move.l  ($FF0002).l,d0
        lea     pm_race_handlers(pc),a0
.l:     move.l  (a0)+,d1
        beq.s   .no
        cmp.l   d1,d0
        bne.s   .l
        btst    #4,($FFFFC80E).w                ; split screen uses plane A
        bne.s   .no
        moveq   #1,d0
        rts
.no:    moveq   #0,d0
        rts

pm_race_handlers:
        dc.l    $00884CB8,$00884CBC,$00885020,$00885024
        dc.l    $00885308,$00885586,$00885618,0

; draw / clear the timing line (main loop context, V-INT may be pending)
pm_timing_update:
        tst.b   (pm_open).l
        bne.s   .done
        bsr     pm_in_race
        tst.b   d0
        beq.s   .not_race
        tst.b   (pm_timing).l
        beq.s   .off
        tst.b   (pm_dirty).l
        beq.s   .flush
        clr.b   (pm_dirty).l
        lea     (pm_fps).l,a2                   ; new numbers: both buffers again
        bsr     pm_build_numbers
        move.b  #3,(pm_fbpend).l
        st      (pm_drawn).l
        bra.s   .flush
.off:   tst.b   (pm_drawn).l                    ; switched off: spaces over it, twice
        beq.s   .flush
        clr.b   (pm_drawn).l
        bsr     pm_build_blank
        move.b  #3,(pm_fbpend).l
.flush: tst.b   (pm_fbpend).l
        bne     pm_fb_flush
.done:  rts
.not_race:
        clr.b   (pm_drawn).l
        clr.b   (pm_fbpend).l
        rts

; text into the 32X frame buffer the 68000 can reach (the one not shown),
; when the SH2 has finished its frame; each buffer once per new text
pm_fb_flush:
        bsr     pm_sh2_done                     ; SH2 frame done: no SH2 frame
        beq.s   .done                           ; buffer access now
        move.b  (PM_MARS_FBC).l,d0              ; FS = buffer shown
        andi.w  #1,d0
        eori.w  #1,d0                           ; the 68000 reaches the other one
        btst    d0,(pm_fbpend).l
        beq.s   .done
        bclr    d0,(pm_fbpend).l
        move    sr,-(sp)
        move    #$2700,sr
        bclr    #7,(PM_MARS_ADAPT).l            ; FM = 0: 68000 owns the frame buffer
        bsr.s   pm_fb_text
        bset    #7,(PM_MARS_ADAPT).l            ; FM = 1
        move    (sp)+,sr
.done:  rts

; the text at PM_BASE+$40 (PM_FB_CHARS characters) in white (32X colour 32)
; on black (colour 1), lines PM_FB_LINE.., centred
pm_fb_text:
        lea     pm_font(pc),a3
        moveq   #0,d7                           ; glyph row 0-7
.row:   move.w  #PM_FB_LINE,d0
        add.w   d7,d0
        add.w   d0,d0
        lea     (PM_FB).l,a1
        moveq   #0,d1
        move.w  (a1,d0.w),d1                    ; line table: line start in words
        add.l   d1,d1
        adda.l  d1,a1
        adda.w  #PM_FB_X,a1
        lea     (PM_BASE+$40).l,a0
.ch:    moveq   #0,d2
        move.b  (a0)+,d2
        beq.s   .next
        subi.w  #$20,d2
        cmpi.w  #63,d2
        bls.s   .ok
        moveq   #0,d2
.ok:    lsl.w   #3,d2
        add.w   d7,d2
        move.b  (a3,d2.w),d3                    ; this glyph row, MSB = left
        moveq   #3,d4                           ; 4 pixel pairs
.pair:  moveq   #1,d5
        lsl.b   #1,d3
        bcc.s   .l0
        moveq   #32,d5
.l0:    lsl.w   #8,d5
        move.b  #1,d5
        lsl.b   #1,d3
        bcc.s   .r0
        move.b  #32,d5
.r0:    move.w  d5,(a1)+
        dbra    d4,.pair
        bra.s   .ch
.next:  addq.w  #1,d7
        cmpi.w  #8,d7
        blo.s   .row
        rts

; "FPS 20 68K 48% LAG 0" from the 3 words at (a2), padded to PM_FB_CHARS
pm_build_numbers:
        lea     (PM_BASE+$40).l,a0              ; build the text in RAM
        lea     pm_t_fps(pc),a1
        bsr.s   pm_cat
        move.w  (a2)+,d0
        bsr     pm_num
        lea     pm_t_cpu(pc),a1
        bsr.s   pm_cat
        move.w  (a2)+,d0
        bsr     pm_num
        lea     pm_t_lag(pc),a1
        bsr.s   pm_cat
        move.w  (a2)+,d0
        bsr     pm_num
pm_pad: lea     (PM_BASE+$40+PM_FB_CHARS).l,a1
.p:     cmpa.l  a1,a0
        bhs.s   .e
        move.b  #' ',(a0)+
        bra.s   .p
.e:     clr.b   (a0)
        rts

pm_build_blank:
        lea     (PM_BASE+$40).l,a0
        bra.s   pm_pad

; the numbers in the pause menu (plane A), row d4, col d5
pm_draw_numbers:
        bsr.s   pm_build_numbers
        move.w  d4,d0
        move.w  d5,d1
        move.w  #PM_ATTR,d3
        lea     (PM_BASE+$40).l,a0
        bra     pm_text

; copy the string (a1) to (a0)+, without its 0
pm_cat: move.b  (a1)+,d0
        beq.s   .e
        move.b  d0,(a0)+
        bra.s   pm_cat
.e:     rts

pm_t_fps:       dc.b    "FPS ",0
pm_t_cpu:       dc.b    " 68K ",0
pm_t_lag:       dc.b    "% LAG ",0
        even

; decimal number d0.w (0-999) to (a0)+
pm_num:
        andi.l  #$FFFF,d0
        divu.w  #100,d0
        tst.w   d0
        beq.s   .tens
        addi.b  #'0',d0
        move.b  d0,(a0)+
        clr.w   d0
        swap    d0
        divu.w  #10,d0
        bra.s   .t2
.tens:  clr.w   d0
        swap    d0
        divu.w  #10,d0
        tst.w   d0
        beq.s   .ones
.t2:    addi.b  #'0',d0
        move.b  d0,(a0)+
.ones:  swap    d0
        addi.b  #'0',d0
        move.b  d0,(a0)+
        rts

; ----------------------------------------------------------------------------
; graphics set-up: font tiles into VRAM, colours into the CRAM shadow
; ----------------------------------------------------------------------------
pm_setup_gfx:
        lea     ($FF84C0).l,a0                  ; palette line 2
        move.w  #$0EEE,2(a0)                    ; 1 white
        move.w  #$0000,6(a0)                    ; 3 black
        move.w  #$0422,8(a0)                    ; 4 dark box
        move.w  #$00EE,$22(a0)                  ; line 3: 1 yellow
        move.w  #$0000,$26(a0)                  ; 3 black
        move.w  #$0422,$28(a0)                  ; 4 dark box
        move.w  #$8F02,(PM_VDP_CTRL).l             ; auto-increment 2
        pm_vram_cmd PM_TILE*32
        move.l  d7,(PM_VDP_CTRL).l
        lea     pm_font(pc),a0
        lea     (PM_VDP_DATA).l,a1
        move.w  #64*8-1,d6                      ; rows of all glyphs
        moveq   #0,d5                           ; previous row (shadow)
.row:   moveq   #0,d0
        move.b  (a0)+,d0                        ; this row
        move.w  d6,d1
        andi.w  #7,d1
        cmpi.w  #7,d1                           ; first row of a glyph
        bne.s   .keep
        moveq   #0,d5
.keep:  move.b  d5,d2                           ; shadow: one right and one down
        move.b  d0,d1
        lsr.b   #1,d1
        or.b    d1,d2
        lsr.b   #1,d5
        or.b    d5,d2
        not.b   d0
        and.b   d0,d2                           ; not where the glyph is lit
        not.b   d0
        move.b  d0,d5                           ; for the next row
        moveq   #0,d3                           ; 8 nibbles
        moveq   #7,d4
.px:    lsl.l   #4,d3
        btst    d4,d0
        beq.s   .sh
        addq.l  #1,d3
        bra.s   .nx
.sh:    btst    d4,d2
        beq.s   .bg
        addq.l  #3,d3
        bra.s   .nx
.bg:    addq.l  #4,d3                           ; background: the dark box colour
.nx:    dbra    d4,.px
        move.l  d3,(a1)
        dbra    d6,.row
        moveq   #8-1,d6                         ; the box tile: colour 4
.box:   move.l  #$44444444,(a1)
        dbra    d6,.box
        rts

; d0 row, d1 col -> VRAM write command for that cell in d7
pm_cell_cmd:
        move.l  d6,-(sp)
        move.w  d0,d7
        lsl.w   #7,d7                           ; * 128 cells
        add.w   d1,d7
        add.w   d7,d7
        addi.w  #PM_ROWS,d7                     ; VRAM address
        moveq   #0,d6
        move.w  d7,d6
        lsr.w   #8,d6
        lsr.w   #6,d6                           ; address bits 15-14
        andi.l  #$3FFF,d7
        swap    d7
        ori.l   #$40000000,d7
        or.w    d6,d7
        move.l  (sp)+,d6
        rts

; text (a0, ends with 0) at row d0, col d1, attribute d3
pm_text:
        bsr.s   pm_cell_cmd
        move.l  d7,(PM_VDP_CTRL).l
.c:     moveq   #0,d2
        move.b  (a0)+,d2
        beq.s   .end
        subi.w  #$20,d2
        cmpi.w  #63,d2
        bls.s   .ok
        moveq   #0,d2
.ok:    addi.w  #PM_TILE,d2
        or.w    d3,d2
        move.w  d2,(PM_VDP_DATA).l
        bra.s   .c
.end:   rts

; fill d2 cells at row d0, col d1 with entry d3
pm_fill:
        bsr.s   pm_cell_cmd
        move.l  d7,(PM_VDP_CTRL).l
        subq.w  #1,d2
.f:     move.w  d3,(PM_VDP_DATA).l
        dbra    d2,.f
        rts

; Z clear: SH2 frame done (COMM1_LO bit 0). The SH2 may be writing the
; register, so read it until two reads agree.
pm_sh2_done:
        move.w  d1,-(sp)
.r:     move.b  (PM_COMM1_LO).l,d1
        cmp.b   (PM_COMM1_LO).l,d1
        bne.s   .r
        btst    #0,d1
        movem.w (sp)+,d1                        ; keeps the flags
        rts

; ----------------------------------------------------------------------------
; pm_set_mode: 32X bitmap mode = d0 (0 blank, 1 packed pixel, the race's).
; The 68000 may write the 32X VDP only while FM = 0, so FM is handed to the
; 68000 for a few instructions, after the SH2 finished its frame.
; ----------------------------------------------------------------------------
pm_set_mode:
        move.l  #200000,d1
.w:     bsr     pm_sh2_done                     ; SH2 frame done
        bne.s   .go
        subq.l  #1,d1
        bne.s   .w
.go:    move    sr,-(sp)
        move    #$2700,sr
        bclr    #7,(PM_MARS_ADAPT).l            ; FM = 0
        move.b  (PM_MARS_MODE).l,d1
        andi.b  #$FC,d1
        or.b    d0,d1
        move.b  d1,(PM_MARS_MODE).l
        bset    #7,(PM_MARS_ADAPT).l            ; FM = 1
        move    (sp)+,sr
        rts

; ----------------------------------------------------------------------------
; the menu
; ----------------------------------------------------------------------------
pm_items:
        dc.l    pm_s_cont+$880000, pm_s_restart+$880000, pm_s_quit+$880000
        dc.l    pm_s_timing+$880000
pm_s_cont:      dc.b    "CONTINUE",0
pm_s_restart:   dc.b    "RETRY COURSE",0
pm_s_quit:      dc.b    "QUIT RACE",0
pm_s_timing:    dc.b    "TIMING",0
pm_s_title:     dc.b    "PAUSED",0
pm_s_ver:       include "../build/pm_stamp.inc"   ; "VR32X V6 mm-dd hh:mm", made by the Makefile
pm_s_help:      dc.b    "UP/DOWN  A/START OK",0
pm_s_on:        dc.b    " ON",0
pm_s_off:       dc.b    "OFF",0
        even

pm_draw_menu:
        moveq   #PM_MENU_H-1,d4                 ; the box
        moveq   #PM_MENU_ROW,d0
.b:     movem.l d0/d4,-(sp)
        moveq   #PM_MENU_COL,d1
        moveq   #PM_MENU_W,d2
        move.w  #PM_ATTR|PM_BOX,d3
        bsr     pm_fill
        movem.l (sp)+,d0/d4
        addq.w  #1,d0
        dbra    d4,.b
        lea     pm_s_title(pc),a0
        moveq   #PM_MENU_ROW+1,d0
        moveq   #PM_MENU_COL+8,d1
        move.w  #PM_ATTR_SEL,d3
        bsr     pm_text
        moveq   #0,d4                           ; the items
.i:     move.w  d4,d0
        addi.w  #PM_MENU_ROW+3,d0
        moveq   #PM_MENU_COL+1,d1
        move.w  #PM_ATTR,d3
        cmp.b   (pm_sel).l,d4
        bne.s   .n
        move.w  #PM_ATTR_SEL,d3
.n:     movem.l d0/d3-d4,-(sp)
        lea     .mark(pc),a0                    ; "> " or "  "
        cmp.b   (pm_sel).l,d4
        beq.s   .m
        lea     .nomark(pc),a0
.m:     bsr     pm_text
        movem.l (sp),d0/d3-d4
        move.w  d4,d1
        lsl.w   #2,d1
        lea     pm_items(pc),a0
        movea.l (a0,d1.w),a0
        moveq   #PM_MENU_COL+3,d1
        bsr     pm_text
        movem.l (sp)+,d0/d3-d4
        cmpi.w  #3,d4                           ; TIMING: ON / OFF
        bne.s   .next
        lea     pm_s_on(pc),a0
        tst.b   (pm_timing).l
        bne.s   .sw
        lea     pm_s_off(pc),a0
.sw:    moveq   #PM_MENU_COL+18,d1
        bsr     pm_text
.next:  addq.w  #1,d4
        cmpi.w  #PM_ITEMS,d4
        blo     .i
        lea     (PM_BASE+$38).l,a2              ; racing numbers from before the pause
        moveq   #PM_MENU_ROW+8,d4
        moveq   #PM_MENU_COL+1,d5
        bsr     pm_draw_numbers
        lea     pm_s_ver(pc),a0
        moveq   #PM_MENU_ROW+9,d0
        moveq   #PM_MENU_COL+1,d1
        move.w  #PM_ATTR,d3
        bsr     pm_text
        lea     pm_s_help(pc),a0
        moveq   #PM_MENU_ROW+10,d0
        moveq   #PM_MENU_COL+1,d1
        move.w  #PM_ATTR,d3
        bra     pm_text
.mark:   dc.b    "> ",0
.nomark: dc.b    "  ",0
        even

pm_clear_menu:
        moveq   #PM_MENU_H-1,d4
        moveq   #PM_MENU_ROW,d0
.c:     movem.l d0/d4,-(sp)
        moveq   #PM_MENU_COL,d1
        moveq   #PM_MENU_W,d2
        moveq   #0,d3
        bsr     pm_fill
        movem.l (sp)+,d0/d4
        addq.w  #1,d0
        dbra    d4,.c
        clr.b   (pm_open).l
        moveq   #1,d0                           ; 32X picture back (packed pixel mode)
        bsr     pm_set_mode
        st      (pm_dirty).l                    ; timing line back at once
        rts

; ----------------------------------------------------------------------------
; pm_pause_tick: pause sub-state [08], once per pause cycle (main loop,
; V-INT idle: the game writes no VDP port meanwhile)
; ----------------------------------------------------------------------------
pm_pause_tick:
        bsr     pm_init
        btst    #4,($FFFFC80E).w                ; split screen: the game's own pause
        beq.s   .one
        jmp     ($00880000+controller_input_check_start_button_handler+8).l
.one:   movem.l d0-d7/a0-a2,-(sp)
        bsr.s   .menu                           ; d0 = 0: stay, 1 continue, 2 quit
        movem.l (sp)+,d0-d7/a0-a2
        tst.b   (PM_BASE+$22).l
        beq.s   .stay
        cmpi.b  #1,(PM_BASE+$22).l
        bne.s   .quit
        jmp     ($00880000+set_timer_val).l     ; CONTINUE: the game's unpause
.quit:  jmp     ($00880000+sound_queue_enable_flags_advance_state).l
.stay:  rts

.menu:  clr.b   (PM_BASE+$22).l
        move.b  #0,($FF69F0).l                  ; no SH2 "PAUSE" text under the menu
        tst.b   (pm_open).l
        bne.s   .input
        st      (pm_open).l
        clr.b   (pm_sel).l
        move.l  (pm_fps).l,(PM_BASE+$38).l     ; the numbers from just before pausing
        move.w  (pm_lagshow).l,(PM_BASE+$3C).l
        moveq   #0,d0                           ; 32X picture off while the menu is up
        bsr     pm_set_mode                     ; (its sky and some 3D colours always
                                                ; show in front of the Genesis planes)
        bsr     pm_setup_gfx
        bra     pm_draw_menu
.input: move.b  ($FFFFC86D).w,d0                ; newly pressed: S A C B R L D U
        btst    #0,d0
        beq.s   .down
        subq.b  #1,(pm_sel).l
        bpl     pm_draw_menu
        move.b  #PM_ITEMS-1,(pm_sel).l
        bra     pm_draw_menu
.down:  btst    #1,d0
        beq.s   .lr
        addq.b  #1,(pm_sel).l
        cmpi.b  #PM_ITEMS,(pm_sel).l
        blo     pm_draw_menu
        clr.b   (pm_sel).l
        bra     pm_draw_menu
.lr:    move.b  d0,d1
        andi.b  #$EC,d1                         ; Start, A, C, Right, Left
        beq.s   .none
        moveq   #0,d5
        move.b  (pm_sel).l,d5
        cmpi.b  #3,d5
        beq.s   .tim
        andi.b  #$E0,d0                         ; actions: Start, A or C only
        beq.s   .none
        bsr     pm_clear_menu
        move.b  #1,(PM_BASE+$22).l              ; continue
        tst.b   d5
        beq.s   .none
        move.b  #2,(PM_BASE+$22).l              ; quit or restart
        clr.b   (pm_restart).l
        cmpi.b  #1,d5
        bne.s   .none
        st      (pm_restart).l
        rts
.tim:   not.b   (pm_timing).l
        bra     pm_draw_menu
.none:  rts

; ----------------------------------------------------------------------------
; pm_quit_stage: pause sub-state [10], after the game's quit teardown
; ----------------------------------------------------------------------------
pm_quit_stage:
        tst.b   (pm_restart).l
        bne.s   .restart
        jmp     ($00880000+sh2_handler_dispatch_scene_init).l
.restart:
        clr.b   (pm_restart).l
        jsr     ($00880000+display_digit_extract).l
        jmp     ($00880000+sh2_scene_reset_name_entry_mode_disp).l  ; course select

        include "modules/68k/optimization/pause_menu_font.asm"
        even
