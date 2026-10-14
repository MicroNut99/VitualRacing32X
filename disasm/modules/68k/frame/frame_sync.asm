; ============================================================================
; Frame Sync & Communication Utilities ($00203A - $00207E)
; ============================================================================
;
; PURPOSE
; -------
; Functions for frame synchronization between 68K and SH2, plus related
; communication variable management. Used at frame boundaries.
;
; MEMORY MAP
; ----------
; | Address    | Name              | Purpose                       |
; |------------|-------------------|-------------------------------|
; | $FFFFC822  | COMM_FLAG_LO      | Communication flag (low byte) |
; | $FFFFC823  | COMM_FLAG_HI      | Communication flag (high byte)|
; | $FFFFC8A2  | COMM_STATUS       | Communication status word     |
; | $FFFFC8A4  | COMM_DATA         | Communication data word/long  |
; | $FFFF8504  | SOUND_PORT_A      | Z80 sound port A              |
; | $FFFF8506  | SOUND_PORT_B      | Z80 sound port B              |
;
; Dependencies: V-INT handler, SH2 communication
; Related: sh2_communication.asm, vint_handler.asm
; ============================================================================
; Format: Proper mnemonics with original bytes in comments for verification
; ============================================================================

; Work RAM addresses (sign-extended for .w addressing)
COMM_FLAG_LO    equ     $FFFFC822   ; Communication flag low byte
COMM_FLAG_HI    equ     $FFFFC823   ; Communication flag high byte
COMM_STATUS     equ     $FFFFC8A2   ; Communication status word
COMM_DATA       equ     $FFFFC8A4   ; Communication data word/long

; Z80 sound ports (sign-extended)
SOUND_PORT_A    equ     $FFFF8504   ; Sound port A (commands)
SOUND_PORT_B    equ     $FFFF8506   ; Sound port B (data)

; Constants
COMM_FLAG_F0    equ     $00F0       ; Communication ready flag
SOUND_INIT_A    equ     $0030       ; Sound port A init value
SOUND_INIT_B    equ     $0003       ; Sound port B init value

        org     $00203A

; ============================================================================
; sh2_frame_sync ($00203A) - SH2 Frame Sync Wrapper
; Purpose: Saves all registers, calls SH2 sync routine, restores registers
; Called by: V-INT handler, main loop
; Parameters: None
; Returns: Nothing (all registers preserved)
;
; This is a register-safe wrapper around the main SH2 sync at $008B0004.
; ============================================================================

sh2_frame_sync:
        movem.l d0-d7/a0-a6,-(sp)               ; $00203A: $48E7 $FFFE - Save D0-D7/A0-A6
        jsr     $008B0004                       ; $00203E: $4EB9 $008B $0004 - Call SH2 sync
        movem.l (sp)+,d0-d7/a0-a6               ; $002044: $4CDF $7FFF - Restore D0-D7/A0-A6
        rts                                     ; $002048: $4E75

; ============================================================================
; clear_comm_vars ($00204A) - Clear Communication Variables
; Purpose: Resets communication state to idle
; Called by: Initialization, state transitions
; Parameters: None
; Returns: Nothing
;
; Clears all communication flags and status variables.
; ============================================================================

clear_comm_vars:
        moveq   #0,d0                           ; $00204A: $7000       - Clear D0
        move.w  d0,COMM_DATA.w                  ; $00204C: $31C0 $C8A4 - Clear COMM_DATA
        move.b  d0,COMM_FLAG_LO.w               ; $002050: $11C0 $C822 - Clear flag low
        move.b  d0,COMM_FLAG_HI.w               ; $002054: $11C0 $C823 - Clear flag high
        move.w  d0,COMM_STATUS.w                ; $002058: $31C0 $C8A2 - Clear status
        rts                                     ; $00205C: $4E75

; ============================================================================
; set_comm_ready ($00205E) - Set Communication Ready Flag
; Purpose: Signals that 68K is ready for communication
; Called by: Frame sync, initialization
; Parameters: None
; Returns: Nothing
;
; Sets COMM_FLAG_LO to $F0, indicating ready state.
; ============================================================================

set_comm_ready:
        move.b  #COMM_FLAG_F0,COMM_FLAG_LO.w    ; $00205E: $11FC $00F0 $C822 - Set ready flag
        rts                                     ; $002064: $4E75

; ============================================================================
; init_sound_ports ($002066) - Initialize Sound Ports and Clear Comm
; Purpose: Sets up Z80 sound ports and clears communication state
; Called by: System initialization
; Parameters: None
; Returns: Nothing
;
; Initializes sound port registers and clears communication variables.
; ============================================================================

init_sound_ports:
        move.b  #SOUND_INIT_B,SOUND_PORT_B.w    ; $002066: $11FC $0003 $8506 - Port B = $03
        move.b  #SOUND_INIT_A,SOUND_PORT_A.w    ; $00206C: $11FC $0030 $8504 - Port A = $30
        moveq   #0,d0                           ; $002072: $7000       - Clear D0
        move.b  d0,COMM_FLAG_LO.w               ; $002074: $11C0 $C822 - Clear flag
        move.l  d0,COMM_DATA.w                  ; $002078: $21C0 $C8A4 - Clear data (long)
        rts                                     ; $00207C: $4E75

; ============================================================================
; stub_return ($00207E) - Stub/Empty Function
; Purpose: Placeholder that just returns
; Called by: Various jump tables
; Parameters: None
; Returns: Nothing
; ============================================================================

stub_return:
        rts                                     ; $00207E: $4E75

; ============================================================================
; SUMMARY
; ============================================================================
;
; Function          | Address | Size | Purpose
; ------------------+---------+------+------------------------------
; sh2_frame_sync    | $00203A | 14B  | Save regs, sync SH2, restore
; clear_comm_vars   | $00204A | 18B  | Clear all comm state
; set_comm_ready    | $00205E | 8B   | Set $F0 ready flag
; init_sound_ports  | $002066 | 22B  | Init sound + clear comm
; stub_return       | $00207E | 2B   | Empty stub
;
; Total: 64 bytes of frame sync utilities
;
; ============================================================================
