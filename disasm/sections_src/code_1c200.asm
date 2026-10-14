; ============================================================================
; Code Section ($01C200-$01E1FF)
;
; Original data: 8 bytes at $01C200-$01C207
; Optimization code: $01C208-$01E1FF (8,184 bytes available)
;
; ADDRESSING:
;   File offsets:  $01C208 - $01E1FF
;   68K addresses: $89C208 - $89E1FF  (= $880000 + file_offset)
;
;   Cross-section callers MUST use absolute 68K addresses:
;     jsr $0089C208    ; NOT jsr vrd_opt_start (wrong address space)
;
;   Within this section, use PC-relative (BSR/BRA) for local calls.
; ============================================================================

        org     $01C200

; --- Original data (preserved byte-identical) ---
        ROMDATA $01C200,$01C208

; ============================================================================
; RESERVED OPTIMIZATION CODE AREA
; File:  $01C208 - $01E1FF (8,184 bytes)
; 68K:   $89C208 - $89E1FF
;
; Originally unused ($FF padding) in the retail ROM. Reserved for future
; 68K optimization routines. Currently filled with $FF to match original.
;
; Optimization modules are in disasm/modules/68k/optimization/ but NOT
; included here until their hook points are activated.
; ============================================================================

; --- S-1: LOD culling enhanced sprite param update (relocated from code_2200) ---
        include "modules/68k/game/render/object_table_sprite_param_update.asm"

; --- VR32X: pause menu and timing line ---
        include "modules/68k/optimization/pause_menu.asm"

        dcb.b   ($01E200-*),$FF
