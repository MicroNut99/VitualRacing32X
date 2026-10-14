; ============================================================================
; Code Section ($000000-$0001FF)
; Generated from ROM bytes - guaranteed accurate
; ============================================================================

        org     $000000

        ROMDATA $000000,$000078
        dc.w    $0088        ; $000078 - V-INT handler (high word)
        dc.w    $1684        ; $00007A - → $00881684 (original handler)
        ROMDATA $00007C,$0001A0
        dc.w    $0000        ; $0001A0 - ROM Start
        ROMDATA $0001A2,$0001A4
        dc.w    $003F        ; $0001A4 - ROM End (4MB)
        ROMDATA $0001A6,$000200
