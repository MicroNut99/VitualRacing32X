; ============================================================================
; Sprite Descriptor Table + SH2 Palette Load ($00E19E-$00E1FE)
; ============================================================================
; DATA ($E19E-$E1BA): 5 sprite descriptors (6 bytes each: flags, offset, id)
; CODE ($E1BC-$E1FE): sh2_palette_load — VDP CRAM init with nested loops
;   Sets up VDP palette transfer ($8F02 auto-inc), writes 28 palette entries
;   in an outer loop of 6 rows × inner loop of 8 colors, then fills 80
;   entries with $0000.
; ============================================================================

; --- 5 Sprite Descriptors ($00E19E-$00E1BA, 30 bytes DATA) ---
sprite_descriptor_table:
        dc.w    $0401        ; $00E19E
        dc.w    $4010        ; $00E1A0
        dc.w    $003A        ; $00E1A2
        dc.w    $0401        ; $00E1A4
        dc.w    $4049        ; $00E1A6
        dc.w    $003B        ; $00E1A8
        dc.w    $0401        ; $00E1AA
        dc.w    $4083        ; $00E1AC
        dc.w    $003A        ; $00E1AE
        dc.w    $0401        ; $00E1B0
        dc.w    $40BC        ; $00E1B2
        dc.w    $003A        ; $00E1B4
        dc.w    $0401        ; $00E1B6
        dc.w    $40F5        ; $00E1B8
        dc.w    $003B        ; $00E1BA

; --- sh2_palette_load ($00E1BC-$00E1FE, 68 bytes CODE) ---
sh2_palette_load:
        move.w  #$8F02,(A5)                     ; $00E1BC  VDP auto-increment = 2
        move.l  #$40000003,(A5)                 ; $00E1C0  VDP CRAM write cmd (addr $0000)
        clr.w   D0                              ; $00E1C6  palette group index = 0
        moveq   #$1B,D3                         ; $00E1C8  D3 = 27 (unused counter?)
        move.w  D0,D1                           ; $00E1CA  D1 = group index copy
        lsl.w   #3,D1                           ; $00E1CC  D1 *= 8 (byte offset per row)
        lea     $0088E20C,A0                    ; $00E1CE  A0 → palette source base
        lea     (A0,D1.W),A0                    ; $00E1D4  A0 += row offset
        move.w  #$0005,D4                       ; $00E1D8  outer loop: 6 rows
.outer_loop:
        move.w  #$0007,D5                       ; $00E1DC  inner loop: 8 colors per row
.inner_loop:
        moveq   #0,D6                           ; $00E1E0  clear high byte
        move.b  (A0,D5.W),D6                    ; $00E1E2  read palette index byte
        addi.w  #$02F0,D6                       ; $00E1E6  add CRAM base offset
        move.w  D6,(A6)                         ; $00E1EA  write to VDP data port
        dbf     D5,.inner_loop                  ; $00E1EC  loop 8 colors
        dbf     D4,.outer_loop                  ; $00E1F0  loop 6 rows
        move.w  #$004F,D4                       ; $00E1F4  fill counter: 80 entries
.fill_loop:
        move.w  #$0000,(A6)                     ; $00E1F8  write $0000 (black)
        dbf     D4,.fill_loop                   ; $00E1FC  loop 80 entries
