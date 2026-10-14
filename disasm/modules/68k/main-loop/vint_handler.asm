; ============================================================================
; V-INT Handler ($001684-$0017EE)
; ============================================================================
;
; PURPOSE
; -------
; The Vertical Interrupt handler is called every frame (~60Hz NTSC) during
; VBlank. It manages the main game state machine via a jump table dispatcher.
;
; ENTRY POINT
; -----------
; Vector at $000078-$00007B points to $00001684 (vint_handler)
;
; STATE MACHINE
; -------------
; Uses state flag at $FFC87A (also written as $C87A.W with signed offset).
; State 0 = idle/no work, handler exits immediately via RTE.
; Non-zero states dispatch through jump table at $0016B2.
;
; State | Address    | Handler Name           | Purpose
; ------+------------+------------------------+----------------------------------
;   0   | $000819FE  | vint_state_common      | VDP sync + work RAM updates
;   1   | $000819FE  | vint_state_common      | (same)
;   2   | $000819FE  | vint_state_common      | (same)
;   4   | $00081A6E  | vint_state_minimal     | Quick VDP status read
;   5   | $00081A72  | vint_state_vdp_sync    | Full VDP synchronization
;   6   | $00081C66  | vint_state_fb_toggle   | Frame buffer toggle
;   7   | $00081ACA  | vint_state_sprite_cfg  | Sprite configuration
;   9   | $00081E42  | vint_state_fb_setup    | Frame buffer setup
;  10   | $00081B14  | vint_state_vdp_config  | VDP configuration
;  11   | $00081A64  | vint_state_transition  | Set next state
;  12   | $00081BA8  | vint_state_complex     | Complex VDP operations
;  13   | $00081E94  | vint_state_fb_palette  | FB + palette update
;  14   | $00081F4A  | vint_state_fb_dma      | Frame buffer DMA
;  15   | $00082010  | vint_state_cleanup     | Clear SH2 flags
;
; FRAME COUNTER
; -------------
; $FFC964 (also $C964.W) is incremented every frame the handler runs.
;
; REGISTER USAGE
; --------------
; All registers D0-D7/A0-A6 are saved on entry and restored on exit.
; Status register set to $2700 (interrupts disabled) during handler.
;
; TIMING CONSTRAINTS
; ------------------
; Must complete within VBlank period (~4500 68K cycles at 7.67MHz).
; Heavy processing deferred to state handlers after VBlank.
;
; Dependencies: State handlers in other modules
; Related: analysis/architecture/STATE_MACHINES.md
; ============================================================================
; Format: Proper mnemonics with original bytes in comments for verification
; ============================================================================

; Memory-mapped addresses
VINT_STATE      equ     $C87A   ; V-INT state flag (word, signed offset)
FRAME_COUNTER   equ     $C964   ; Frame counter (long)
CTRL_PORT1      equ     $FE92   ; Controller port 1 state
CTRL_PORT2      equ     $FE93   ; Controller port 2 state
BUTTON_MAP      equ     $FE82   ; Button remapping table
CTRL_TYPE       equ     $C810   ; Controller type flag
CTRL_STATE      equ     $C86C   ; Controller state block
CTRL_ALT        equ     $C86E   ; Alternate controller state

; I/O addresses
IO_DATA1        equ     $A10003 ; Controller 1 data port
IO_DATA2        equ     $A10005 ; Controller 2 data port
CTRL_DEST       equ     $FF60D0 ; Controller state destination
CTRL_INPUT      equ     $C970   ; Input buffer

; Status register values
SR_DISABLE_INT  equ     $2700   ; Disable all interrupts
SR_ENABLE_INT   equ     $2300   ; Enable V-INT (level 6)

        org     $001684

; ============================================================================
; vint_handler ($001684) - V-INT Entry Point
; Called by: V-INT vector at $000078
; Parameters: None
; Returns: Via RTE
; ============================================================================

vint_handler:
        tst.w   VINT_STATE.w                    ; $001684: $4A78 $C87A - Test state flag
        beq.s   vint_early_exit                 ; $001688: $6726       - Exit if 0 (no work)
        move    #SR_DISABLE_INT,sr              ; $00168A: $46FC $2700 - Disable interrupts
        movem.l d0-d7/a0-a6,-(sp)               ; $00168E: $48E7 $FFFE - Save all registers
        move.w  VINT_STATE.w,d0                 ; $001692: $3038 $C87A - Get state index
        move.w  #0,VINT_STATE.w                 ; $001696: $31FC $0000 $C87A - Clear state
        movea.l jmp_table(pc,d0.w),a1           ; $00169C: $227B $0014 - Get handler address
        jsr     (a1)                            ; $0016A0: $4E91       - Call state handler
        addq.l  #1,FRAME_COUNTER.w              ; $0016A2: $52B8 $C964 - Increment frame count
        movem.l (sp)+,d0-d7/a0-a6               ; $0016A6: $4CDF $7FFF - Restore registers
        move    #SR_ENABLE_INT,sr               ; $0016AA: $46FC $2300 - Re-enable interrupts
        rte                                     ; $0016AE: $4E73       - Return from exception

vint_early_exit:
        rte                                     ; $0016B0: $4E73       - Quick exit (no work)

; ============================================================================
; STATE HANDLER JUMP TABLE ($0016B2)
; Each entry is a 32-bit address to the handler function
; State index * 4 = table offset (state passed in D0)
; Handlers are in ROM at $0088xxxx (after 32X address remap)
; ============================================================================
jmp_table:
        dc.l    $008819FE   ; $0016B2 State 0: vint_state_common
        dc.l    $008819FE   ; $0016B6 State 1: vint_state_common
        dc.l    $008819FE   ; $0016BA State 2: vint_state_common
        dc.l    $00018200   ; $0016BE State 3: (gap/invalid)
        dc.l    $00881A6E   ; $0016C2 State 4: vint_state_minimal
        dc.l    $00881A72   ; $0016C6 State 5: vint_state_vdp_sync
        dc.l    $00881C66   ; $0016CA State 6: vint_state_fb_toggle
        dc.l    $00881ACA   ; $0016CE State 7: vint_state_sprite_cfg
        dc.l    $008819FE   ; $0016D2 State 8: vint_state_common
        dc.l    $00881E42   ; $0016D6 State 9: vint_state_fb_setup
        dc.l    $00881B14   ; $0016DA State 10: vint_state_vdp_config
        dc.l    $00881A64   ; $0016DE State 11: vint_state_transition
        dc.l    $00881BA8   ; $0016E2 State 12: vint_state_complex
        dc.l    $00881E94   ; $0016E6 State 13: vint_state_fb_palette
        dc.l    $00881F4A   ; $0016EA State 14: vint_state_fb_dma
        dc.l    $00882010   ; $0016EE State 15: vint_state_cleanup
        dc.l    $00000001   ; $0016F2 (extended states marker)
        dc.l    $00881DBE   ; $0016F6 State 16+
        dc.l    $00000001   ; $0016FA (padding)
        dc.l    $00000001   ; $0016FE (padding)
        dc.l    $00000001   ; $001702 (padding)
        dc.l    $00881D0C   ; $001706 State 21+

vint_return:
        rte                                     ; $00170A: $4E73 - Alternate return point

; ============================================================================
; controller_port_init ($00170C) - Initialize Controller Ports
; Sets up I/O port configuration and button mapping tables
; Called by: Initialization sequence
; Parameters: None
; Returns: Nothing
; ============================================================================
controller_port_init:
        move.b  #0,CTRL_PORT1.w                 ; $00170C: $11FC $0000 $FE92 - Clear port1
        move.b  #0,CTRL_PORT2.w                 ; $001712: $11FC $0000 $FE93 - Clear port2
        lea     BUTTON_MAP.w,a1                 ; $001718: $43F8 $FE82 - Button map base
; Initialize button mapping for player 1 (8 buttons)
        move.b  #$04,(a1)+                      ; $00171C: $12FC $0004 - Button 0
        move.b  #$06,(a1)+                      ; $001720: $12FC $0006 - Button 1
        move.b  #$01,(a1)+                      ; $001724: $12FC $0001 - Button 2
        move.b  #$00,(a1)+                      ; $001728: $12FC $0000 - Button 3
        move.b  #$05,(a1)+                      ; $00172C: $12FC $0005 - Button 4
        move.b  #$0A,(a1)+                      ; $001730: $12FC $000A - Button 5
        move.b  #$09,(a1)+                      ; $001734: $12FC $0009 - Button 6
        move.b  #$08,(a1)+                      ; $001738: $12FC $0008 - Button 7
; Initialize button mapping for player 2 (8 buttons)
        move.b  #$04,(a1)+                      ; $00173C: $12FC $0004 - Button 0
        move.b  #$06,(a1)+                      ; $001740: $12FC $0006 - Button 1
        move.b  #$01,(a1)+                      ; $001744: $12FC $0001 - Button 2
        move.b  #$00,(a1)+                      ; $001748: $12FC $0000 - Button 3
        move.b  #$05,(a1)+                      ; $00174C: $12FC $0005 - Button 4
        move.b  #$0A,(a1)+                      ; $001750: $12FC $000A - Button 5
        move.b  #$09,(a1)+                      ; $001754: $12FC $0009 - Button 6
        move.b  #$08,(a1)                       ; $001758: $12BC $0008 - Button 7 (no post-inc)
; Set up controller type tables
        lea     CTRL_INPUT.w,a1                 ; $00175C: $43F8 $FE94 - Alternate: LEA $FE94.W,A1
        lea     .ctrl_table_6btn(pc),a3         ; $001760: $47FA $0034 - 6-button table
        btst    #0,CTRL_TYPE.w                  ; $001764: $0838 $0000 $C818 - Check type
        bne.s   .use_6btn                       ; $00176A: $6604       - Use 6-button if set
        lea     .ctrl_table_3btn(pc),a3         ; $00176C: $47FA $0020 - 3-button table
.use_6btn:
        bsr.s   .copy_table                     ; $001770: $4EBA $0012 - Copy first table
        lea     .ctrl_table_3btn(pc),a3         ; $001774: $47FA $0020 - Default second
        btst    #1,CTRL_TYPE.w                  ; $001778: $0838 $0001 $C818 - Check type 2
        bne.s   .copy_table                     ; $00177E: $6604       - Copy if set
        lea     .ctrl_table_6btn2(pc),a3        ; $001780: $47FA $000C - Alt second table

; Copy 8-byte table from A3 to A1
.copy_table:
        moveq   #7,d7                           ; $001784: $7E07       - 8 bytes
.copy_loop:
        move.b  (a3)+,(a1)+                     ; $001786: $12DB       - Copy byte
        dbra    d7,.copy_loop                   ; $001788: $51CF $FFFC - Loop
        rts                                     ; $00178C: $4E75

; Controller type tables (8 bytes each)
.ctrl_table_6btn2:
        dc.b    $04,$06,$01,$00,$05,$0A,$09,$08 ; $00178E: 6-button alt
.ctrl_table_3btn:
        dc.b    $04,$06,$01,$00,$05,$0A,$09,$08 ; $001796: 3-button

; ============================================================================
; poll_controllers ($00179E) - Read Controller Input (12 calls/frame)
; Reads both ports, handles 3/6-button detection, edge detection
; Called by: V-INT state handlers
; Parameters: None
; Returns: Updates controller state at $C86C-$C86F
; ============================================================================
poll_controllers:
        cmpi.b  #$0D,CTRL_TYPE.w                ; $00179E: $0C38 $000D $C810 - Check type
        bne.s   .no_controllers                 ; $0017A4: $6630       - Skip if no controllers
        lea     CTRL_STATE.w,a0                 ; $0017A6: $41F8 $C86C - State storage
        move.l  (a0),CTRL_DEST                  ; $0017AA: $23D0 $00FF $60D0 - Copy to dest
        lea     IO_DATA1,a1                     ; $0017B0: $43F9 $00A1 $0003 - Port 1
        lea     CTRL_INPUT.w,a2                 ; $0017B6: $45F8 $C970 - Input buffer
        lea     BUTTON_MAP.w,a3                 ; $0017BA: $47F8 $FE82 - Button map
        bsr.s   zbus_request                    ; $0017BE: $4EBA $009E - Request Z80 bus
        bsr.s   button_remap                    ; $0017C2: $4EBA $002A - Remap buttons
        move.b  #0,CTRL_ALT.w                   ; $0017CE: $11FC $0000 $C86E - Clear alt
        rts                                     ; $0017D4: $4E75

.no_controllers:
        move.b  #0,CTRL_STATE.w                 ; $0017D6: $11FC $0000 $C86C - Clear state
        move.b  #0,CTRL_ALT.w                   ; $0017DC: $11FC $0000 $C86E - Clear alt
        rts                                     ; $0017E2: $4E75

.read_port2:
        lea     IO_DATA2,a1                     ; $0017E4: $43F9 $00A1 $0005 - Port 2
        bsr.s   zbus_request                    ; $0017EA: $4EBA $0072 - Request bus

; ============================================================================
; button_remap ($0017EE) - Button Remapping Function
; Remaps physical buttons to logical game buttons based on mapping table
; ============================================================================
button_remap:
        ; (Implementation continues...)
        rts                                     ; placeholder

; ============================================================================
; zbus_request ($00185E) - Z-Bus Request
; Requests access to Z80 bus for controller I/O
; ============================================================================
zbus_request:
        ; (Implementation at $00185E)
        rts                                     ; placeholder
