; ============================================================================
; Camera DMA Transfer (Data Prefix)
; ROM Range: $012BFA-$012C9E (164 bytes)
; ============================================================================
; Category: game
; Purpose: Data prefix (144 bytes) containing 6 sprite reference longwords
;   at $012BFA, followed by 6 sprite descriptors (16 bytes each) at $012C12,
;   and a palette pointer table (6 longwords) at $012C72.
;   Executable code at fn_12200_025_exec: MemoryInit, display mode, state advance.
;
; Uses: D0
; RAM:
;   $C87E: game_state (word, advanced by 4)
; Calls:
;   MemoryInit: memory initialization
; ============================================================================

camera_dma_xfer:
; --- 6 sprite reference longwords (DATA) ---
        dc.w    $222B,$5FF6                     ; $012BFA  sprite ref[0]
        dc.w    $222B,$710A                     ; $012BFE  sprite ref[1]
        dc.w    $222B,$9122                     ; $012C02  sprite ref[2]
        dc.w    $222B,$A9F0                     ; $012C06  sprite ref[3]
        dc.w    $222B,$C8F4                     ; $012C0A  sprite ref[4]
        dc.w    $222B,$5FF6                     ; $012C0E  sprite ref[5]
; --- sprite descriptor 0 (16 bytes, DATA): flag=$0000 Y=$FFB0 X=$0060 W=$0140 ---
        dc.w    $0000,$FFB0,$0060,$0140         ; $012C12
        dc.w    $0000,$0000,$0000,$0000         ; $012C1A  padding
; --- sprite descriptor 1 (16 bytes, DATA): flag=$0000 Y=$FFB0 X=$0060 W=$0140 ---
        dc.w    $0000,$FFB0,$0060,$0140         ; $012C22
        dc.w    $0000,$0000,$0000,$0000         ; $012C2A  padding
; --- sprite descriptor 2 (16 bytes, DATA): flag=$0000 Y=$FFB0 X=$0070 W=$0140 ---
        dc.w    $0000,$FFB0,$0070,$0140         ; $012C32
        dc.w    $0000,$0000,$0000,$0000         ; $012C3A  padding
; --- sprite descriptor 3 (16 bytes, DATA): flag=$0000 Y=$FFA0 X=$0080 W=$0180 ---
        dc.w    $0000,$FFA0,$0080,$0180         ; $012C42
        dc.w    $0000,$0000,$0000,$0000         ; $012C4A  padding
; --- sprite descriptor 4 (16 bytes, DATA): flag=$0000 Y=$FF10 X=$0050 W=$0140 ---
        dc.w    $0000,$FF10,$0050,$0140         ; $012C52
        dc.w    $0000,$0000,$0000,$0000         ; $012C5A  padding
; --- sprite descriptor 5 (16 bytes, DATA): flag=$0000 Y=$FFB0 X=$0060 W=$0140 ---
        dc.w    $0000,$FFB0,$0060,$0140         ; $012C62
        dc.w    $0000,$0000,$0000,$0000         ; $012C6A  padding
; --- palette pointer table (6 longword pointers, DATA) ---
        dc.l    $008BBBDC                       ; $012C72  palette ptr[0]
        dc.l    $008BBCDC                       ; $012C76  palette ptr[1]
        dc.l    $008BBBDC                       ; $012C7A  palette ptr[2]
        dc.l    $008BBDDC                       ; $012C7E  palette ptr[3]
        dc.l    $008BBEDC                       ; $012C82  palette ptr[4]
        dc.l    $008BBBDC                       ; $012C86  palette ptr[5]
; --- executable code ---
fn_12200_025_exec:
        clr.w   D0                              ; $012C8A  mode = 0
        bsr.w   MemoryInit              ; $6100 $B89E
        move.w  #$0020,$00FF0008                ; $012C90  display mode = $0020
        addq.w  #4,($FFFFC87E).w                ; $012C98  advance game_state
        rts                                     ; $012C9C
