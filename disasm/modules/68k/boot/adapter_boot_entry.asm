; ============================================================================
; 32X Adapter Boot Entry ($0003C0-$000511)
;
; Contains the MARS adapter initialization sequence:
;   $0003C0-$0003CF: "MARS CHECK MODE " identification string
;   $0003D0-$0003EF: 32X boot parameters (stack pointers, SH2 entry points)
;   $0003F0-$0004D3: 68K-side adapter boot code (register setup, MARS handshake,
;                     VDP init, Z80 program load, jump to main)
;   $0004D4-$0004E7: VDP register initialization data table (20 bytes)
;   $0004E8-$000511: Z80 program data (42 bytes, loaded into Z80 RAM)
;
; WARNING: The MARS CHECK string at $0003C0 is verified by the 32X hardware
; during boot. Do not modify the first 16 bytes.
; ============================================================================

; --- "MARS CHECK MODE " identification string (DATA -- verified by hardware) ---
adapter_boot_entry:
        dc.w    $4D41                           ; $0003C0 - 'MA'
        dc.w    $5253                           ; $0003C2 - 'RS'
        dc.w    $2043                           ; $0003C4 - ' C'
        dc.w    $4845                           ; $0003C6 - 'HE'
        dc.w    $434B                           ; $0003C8 - 'CK'
        dc.w    $204D                           ; $0003CA - ' M'
        dc.w    $4F44                           ; $0003CC - 'OD'
        dc.w    $4520                           ; $0003CE - 'E '

; --- 32X boot parameters (DATA -- stack pointers, SH2 entry points) ---
        dc.w    $0000,$0000                     ; $0003D0 - (reserved)
        dc.w    $0002,$0000                     ; $0003D4 - Master SH2 stack pointer = $00020000
        dc.w    $0000,$0000                     ; $0003D8 - (reserved)
        dc.w    $0000,$C000                     ; $0003DC - Slave SH2 stack pointer = $0000C000
        dc.w    $0600,$0280                     ; $0003E0 - Master SH2 entry PC = $06000280
        dc.w    $0600,$0288                     ; $0003E4 - Slave SH2 entry PC = $06000288
        dc.w    $0600,$0000                     ; $0003E8 - Master SH2 VBR = $06000000
        dc.w    $0600,$0140                     ; $0003EC - Slave SH2 VBR = $06000140

; === 68K adapter boot code ($0003F0-$0004D3) =================================

        movea.l #$FFFFFFC0,a4                   ; $0003F0 - A4 = register save area
        move.l  #$00000000,($00A15128).l        ; $0003F6 - Clear MARS system flag
        move.w  #$2700,sr                       ; $000400 - Disable all interrupts
        lea     ($00A10000).l,a5                ; $000404 - A5 = MARS system register base
        moveq   #1,d0                           ; $00040A - D0 = 1 (for BTST below)
        cmpi.l  #$4D415253,$30EC(a5)            ; $00040C - Check 'MARS' signature at adapter ID
        dc.w    $6600,$03E6                     ; $000414 - BNE.W to system_boot_init .loc_0140 (cross-file, local label)
.label_0418:
        btst    #7,$5101(a5)                    ; $000418 - Poll adapter RES bit (bit 7)
        beq.s   .label_0418                     ; $00041E - Wait until adapter reset complete
        tst.l   $0008(a5)                       ; $000420 - Check MARS interrupt vector
        beq.s   .label_0436                     ; $000424 - Skip if zero (fresh boot)
        tst.w   $000C(a5)                       ; $000426 - Check MARS status word
        beq.s   .label_0436                     ; $00042A - Skip if zero (fresh boot)
        btst    #0,$5101(a5)                    ; $00042C - Check adapter ADEN bit (bit 0)
        dc.w    $6600,$03B8                     ; $000432 - BNE.W to system_boot_init (cross-file, local label)
.label_0436:
        move.b  $0001(a5),d0                    ; $000436 - Read MARS adapter control byte
        andi.b  #$0F,d0                         ; $00043A - Mask low nibble (FM access bits)
        beq.s   .label_0446                     ; $00043E - Skip if no FM bits set
        move.l  ($055A).w,$4000(a5)             ; $000440 - Copy FM access vector to MARS area
.label_0446:
        moveq   #0,d1                           ; $000446 - D1 = 0
        movea.l d1,a6                           ; $000448 - A6 = 0
        move    a6,usp                          ; $00044A - Clear user stack pointer

; --- VDP initialization ---
        lea     ($000004D4).l,a0                ; $00044C - A0 = VDP register init table
        bsr.w   vdp_reg_table_load+148          ; $000452 - BSR.W to vdp_reg_table_load code entry
        bsr.w   vdp_vram_clear_via_dma          ; $000456 - BSR.W clear VRAM via DMA

; --- Z80 program load ---
        lea     ($000004E8).l,a3                ; $00045A - A3 = Z80 program data source
        lea     ($00A00000).l,a1                ; $000460 - A1 = Z80 RAM base
        lea     ($00C00011).l,a2                ; $000466 - A2 = Z80 bus request register
        move.w  #$0100,d7                       ; $00046C - D7 = Z80 bus request value
        moveq   #0,d0                           ; $000470 - D0 = 0 (for bus release + BTST)
        move.w  d7,$1100(a5)                    ; $000472 - Request Z80 bus via MARS
        move.w  d7,$1200(a5)                    ; $000476 - Request Z80 reset via MARS
.label_047A:
        btst    d0,$1100(a5)                    ; $00047A - Poll Z80 bus grant (bit 0)
        bne.s   .label_047A                     ; $00047E - Wait until bus granted
        moveq   #$25,d2                         ; $000480 - D2 = 37 (Z80 program size - 1)
.label_0482:
        move.b  (a3)+,(a1)+                     ; $000482 - Copy Z80 program byte
        dbf     d2,.label_0482                  ; $000484 - Loop 38 bytes total
        move.w  d0,$1200(a5)                    ; $000488 - Release Z80 reset
        move.w  d0,$1100(a5)                    ; $00048C - Release Z80 bus
        move.w  d7,$1200(a5)                    ; $000490 - Assert Z80 reset (start Z80)
        move.b  (a3)+,(a2)                      ; $000494 - Write Z80 bus request port (4 writes
        move.b  (a3)+,(a2)                      ; $000496 -   to same address -- hardware handshake
        move.b  (a3)+,(a2)                      ; $000498 -   for Z80 bus release sequence after
        move.b  (a3)+,(a2)                      ; $00049A -   program load)

; --- Copy trampoline to 68K Work RAM and jump ---
        lea     ($000004C0).l,a0                ; $00049C - A0 = trampoline source (in ROM)
        lea     ($00FF0000).l,a1                ; $0004A2 - A1 = 68K Work RAM base
        move.l  (a0)+,(a1)+                     ; $0004A8 - Copy 32 bytes of trampoline
        move.l  (a0)+,(a1)+                     ; $0004AA -   to Work RAM (8 longwords)
        move.l  (a0)+,(a1)+                     ; $0004AC
        move.l  (a0)+,(a1)+                     ; $0004AE
        move.l  (a0)+,(a1)+                     ; $0004B0
        move.l  (a0)+,(a1)+                     ; $0004B2
        move.l  (a0)+,(a1)+                     ; $0004B4
        move.l  (a0)+,(a1)+                     ; $0004B6
        lea     ($00FF0000).l,a0                ; $0004B8 - A0 = Work RAM trampoline entry
        jmp     (a0)                            ; $0004BE - Jump to trampoline in RAM

; --- Trampoline code (copied to $00FF0000, enables adapter then jumps to main) ---
        move.b  #1,$5101(a5)                    ; $0004C0 - Set ADEN bit -- enable 32X adapter
        lea     ($000006BC).l,a0                ; $0004C6 - A0 = main entry ROM offset
        adda.l  #$00880000,a0                   ; $0004CC - Convert to 68K address space
        jmp     (a0)                            ; $0004D2 - Jump to main ($008806BC)

; === VDP register initialization data ($0004D4-$0004E7, 20 bytes DATA) ========
; Byte table loaded by vdp_reg_table_load into VDP registers $80-$92.
        dc.w    $0404                           ; $0004D4 - VDP reg $80=$04, $81=$04
        dc.w    $303C                           ; $0004D6 - VDP reg $82=$30, $83=$3C
        dc.w    $076C                           ; $0004D8 - VDP reg $84=$07, $85=$6C
        dc.w    $0000                           ; $0004DA - VDP reg $86=$00, $87=$00
        dc.w    $0000                           ; $0004DC - VDP reg $88=$00, $89=$00
        dc.w    $FF00                           ; $0004DE - VDP reg $8A=$FF, $8B=$00
        dc.w    $8137                           ; $0004E0 - VDP reg $8C=$81, $8D=$37
        dc.w    $0002                           ; $0004E2 - VDP reg $8E=$00, $8F=$02
        dc.w    $0100                           ; $0004E4 - VDP reg $90=$01, $91=$00
        dc.w    $0000                           ; $0004E6 - VDP reg $92=$00 + pad byte

; === Z80 program data ($0004E8-$000511, 42 bytes DATA) ========================
; Loaded into Z80 RAM at $00A00000. Z80 init/sound driver stub.
        dc.w    $AF01                           ; $0004E8
        dc.w    $D91F                           ; $0004EA
        dc.w    $1127                           ; $0004EC
        dc.w    $0021                           ; $0004EE
        dc.w    $2600                           ; $0004F0
        dc.w    $F977                           ; $0004F2
        dc.w    $EDB0                           ; $0004F4
        dc.w    $DDE1                           ; $0004F6
        dc.w    $FDE1                           ; $0004F8
        dc.w    $ED47                           ; $0004FA
        dc.w    $ED4F                           ; $0004FC
        dc.w    $D1E1                           ; $0004FE
        dc.w    $F108                           ; $000500
        dc.w    $D9C1                           ; $000502
        dc.w    $D1E1                           ; $000504
        dc.w    $F1F9                           ; $000506
        dc.w    $F3ED                           ; $000508
        dc.w    $5636                           ; $00050A
        dc.w    $E9E9                           ; $00050C
        dc.w    $9FBF                           ; $00050E
        dc.w    $DFFF                           ; $000510
