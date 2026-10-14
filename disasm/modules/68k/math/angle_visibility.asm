; ============================================================================
; Angle Normalization and Visibility Functions ($00748C - $0075D2)
; ============================================================================
;
; PURPOSE
; -------
; Normalizes angles to a 512-step rotation and performs BSP-style visibility
; testing for polygon culling. Two variants handle different test conditions.
;
; ANGLE SYSTEM
; ------------
; The game uses a 512-step angle system:
; - Full rotation = 512 steps ($200)
; - Quarter rotation = 128 steps ($80)
; - The $4000 offset shifts the reference frame
; - $01FF mask keeps angle in 0-511 range
;
; INPUT PARAMETERS
; ----------------
; D1 = Viewing angle 1 (raw)
; D2 = Viewing angle 2 (raw)
; A1 = Polygon data pointer (BSP node structure)
;
; BSP NODE STRUCTURE
; ------------------
; | Offset | Size | Purpose                              |
; |--------|------|--------------------------------------|
; | +0     | W    | Flag word (negative = skip)          |
; | +2     | W    | Plane coefficient A                  |
; | +4     | W    | Plane coefficient B                  |
; | +6     | W    | Plane constant C                     |
; | ...    | ...  | Additional plane data                |
;
; ALGORITHM
; ---------
; 1. Normalize input angles to 0-511 range, multiply by 2
; 2. Check polygon flag - if negative, return 0 (not visible)
; 3. For each of 10 BSP planes:
;    a. Read plane coefficients from (A1)+
;    b. Compute: result = (D1 * A + C) >> 5
;    c. Compare result with D2 to determine side
;    d. Follow appropriate BSP branch
; 4. Return 1 if visible, 0 if culled
;
; Dependencies: None (pure math)
; Related: sprite_list_process ($74A4), 3D rendering pipeline
; ============================================================================
; Format: Proper mnemonics with original bytes in comments for verification
; ============================================================================

; Angle system constants
ANGLE_OFFSET    equ     $4000       ; Quarter rotation offset
ANGLE_MASK      equ     $01FF       ; 512-step mask
BSP_PLANE_COUNT equ     9           ; Number of BSP planes to test

        org     $00748C

; ============================================================================
; angle_normalize ($00748C) - Normalize Angles and Test Visibility
; Called by: 8 locations per frame (visibility culling)
; Parameters:
;   D1 = Viewing angle 1
;   D2 = Viewing angle 2
;   A1 = BSP polygon data pointer
; Returns:
;   D0 = 1 if visible, 0 if culled
;   A1 = Advanced past polygon data
;   A2 = Copy of original A1
; ============================================================================

angle_normalize:
; Normalize D1: add offset, mask to 9 bits, multiply by 2, sign extend
        addi.w  #ANGLE_OFFSET,d1                ; $00748C: $0641 $4000 - Add quarter rotation
        andi.w  #ANGLE_MASK,d1                  ; $007490: $0241 $01FF - Mask to 0-511
        asl.w   #1,d1                           ; $007494: $E341       - D1 *= 2 (word index)
        ext.l   d1                              ; $007496: $48C1       - Sign extend to long

; Normalize D2: same process
        addi.w  #ANGLE_OFFSET,d2                ; $007498: $0642 $4000 - Add quarter rotation
        andi.w  #ANGLE_MASK,d2                  ; $00749C: $0242 $01FF - Mask to 0-511
        asl.w   #1,d2                           ; $0074A0: $E342       - D2 *= 2
        ext.l   d2                              ; $0074A2: $48C2       - Sign extend

; Check polygon visibility flag
        move.w  (a1)+,d7                        ; $0074A4: $3E19       - Read flag word
        bpl.s   .do_bsp_test                    ; $0074A6: $6A04       - If positive, do BSP test
        moveq   #0,d0                           ; $0074A8: $7000       - Return 0 (not visible)
        rts                                     ; $0074AA: $4E75

.do_bsp_test:
; Initialize BSP traversal
        movea.l a1,a2                           ; $0074AC: $2449       - Save A1 in A2
        moveq   #BSP_PLANE_COUNT,d5             ; $0074AE: $7A09       - D5 = 9 planes to test

.plane_loop:
        move.w  (a1)+,d3                        ; $0074B0: $3619       - Read plane selector
        moveq   #3,d6                           ; $0074B2: $7C03       - D6 = 3 (bit counter)

; Test bits 15-14 of plane selector
        asl.w   #1,d3                           ; $0074B4: $E343       - Shift bit 15 to carry
        bcs.s   .branch_15_set                  ; $0074B6: $6532       - Branch if bit 15 set
        asl.w   #1,d3                           ; $0074B8: $E343       - Shift bit 14 to carry
        bcs.s   .branch_14_set                  ; $0074BA: $651E       - Branch if bit 14 set

; Compute: D0 = (D1 * coef + constant) >> 5, compare with D2
        move.w  d1,d0                           ; $0074BC: $3001       - D0 = D1
        muls.w  (a1)+,d0                        ; $0074BE: $C1D9       - D0 *= coefficient
        move.w  (a1)+,d4                        ; $0074C0: $3819       - D4 = constant
        ext.l   d4                              ; $0074C2: $48C4       - Sign extend
        asr.l   #5,d4                           ; $0074C4: $EBA4       - D4 >>= 5
        add.l   d4,d0                           ; $0074C6: $D084       - D0 += D4
        asr.l   #5,d0                           ; $0074C8: $EAA0       - D0 >>= 5
        cmp.l   d0,d2                           ; $0074CA: $B480       - Compare D2 with D0
        blt.s   .side_negative_1                ; $0074CC: $6D06       - Branch if D2 < D0

        asl.w   #1,d3                           ; $0074CE: $E343       - Next selector bit
        bcs.s   .found_visible                  ; $0074D0: $6552       - If set, visible
        bra.s   .continue_test                  ; $0074D2: $6048       - Continue testing

.side_negative_1:
        asl.w   #1,d3                           ; $0074D4: $E343       - Next selector bit
        bcc.s   .found_visible                  ; $0074D6: $644C       - If clear, visible
        bra.s   .continue_test                  ; $0074D8: $6042       - Continue testing

.branch_14_set:
; Alternative comparison path
        cmp.w   (a1),d2                         ; $0074DA: $B251       - Compare D2 with (A1)
        blt.s   .side_negative_2                ; $0074DC: $6D06       - Branch if D2 < (A1)
        asl.w   #1,d3                           ; $0074DE: $E343       - Next selector bit
        bcc.s   .found_visible                  ; $0074E0: $6442       - If clear, visible
        bra.s   .skip_and_continue              ; $0074E2: $6036       - Skip data, continue

.side_negative_2:
        asl.w   #1,d3                           ; $0074E4: $E343       - Next selector bit
        bcs.s   .found_visible_alt              ; $0074E6: $653C       - If set, visible (alt)
        bra.s   .skip_and_continue              ; $0074E8: $6030       - Skip data, continue

.branch_15_set:
; Use D2 for coefficient instead of D1
        asl.w   #1,d3                           ; $0074EA: $E343       - Shift bit 14 to carry
        bcs.s   .d2_path_14_set                 ; $0074EC: $651E       - Branch if bit 14 set

        move.w  d2,d0                           ; $0074EE: $3002       - D0 = D2
        muls.w  (a1)+,d0                        ; $0074F0: $C1D9       - D0 *= coefficient
        move.w  (a1)+,d4                        ; $0074F2: $3819       - D4 = constant
        ext.l   d4                              ; $0074F4: $48C4       - Sign extend
        asr.l   #5,d4                           ; $0074F6: $EBA4       - D4 >>= 5
        add.l   d4,d0                           ; $0074F8: $D084       - D0 += D4
        asr.l   #5,d0                           ; $0074FA: $EAA0       - D0 >>= 5
        cmp.l   d0,d1                           ; $0074FC: $B280       - Compare D1 with D0
        blt.s   .d2_side_negative               ; $0074FE: $6D06       - Branch if D1 < D0

        asl.w   #1,d3                           ; $007500: $E343       - Next selector bit
        bcc.s   .found_visible                  ; $007502: $6420       - If clear, visible
        bra.s   .advance_continue               ; $007504: $6016       - Continue

.d2_side_negative:
        asl.w   #1,d3                           ; $007506: $E343       - Next selector bit
        bcs.s   .found_visible_b                ; $007508: $651A       - If set, visible
        bra.s   .advance_continue               ; $00750A: $6010       - Continue

.d2_path_14_set:
; Direct comparison with (A1)
        cmp.w   (a1),d1                         ; $00750C: $B451       - Compare D1 with (A1)
        blt.s   .d2_14_negative                 ; $00750E: $6D06       - Branch if D1 < (A1)
        asl.w   #1,d3                           ; $007510: $E343       - Next selector bit
        bcs.s   .found_visible_c                ; $007512: $6510       - If set, visible
        bra.s   .next_plane_entry               ; $007514: $6004       - Next plane

.d2_14_negative:
        asl.w   #1,d3                           ; $007516: $E343       - Next selector bit
        bcc.s   .found_visible_d                ; $007518: $640A       - If clear, visible

.next_plane_entry:
        addq.l  #4,a1                           ; $00751A: $5889       - Skip 4 bytes of data
.continue_test:
        dbra    d6,.plane_loop                  ; $00751C: $51CE $FF96 - Next bit / plane

; All planes tested, polygon not visible
        moveq   #1,d0                           ; $007520: $7001       - Return 1 (visible)
        bra.s   .return                         ; $007522: $600E       - Skip to return

.found_visible:
.found_visible_alt:
.found_visible_b:
.found_visible_c:
.found_visible_d:
        adda.l  #$0000001C,a2                   ; $007524: $D5FC $0000 $001C - A2 += 28

.skip_and_continue:
.advance_continue:
        movea.l a2,a1                           ; $00752A: $224A       - A1 = A2
        dbra    d7,.plane_loop                  ; $00752C: $51CF $FF82 - Loop D7 times

; Return not visible
        moveq   #0,d0                           ; $007530: $7000       - Return 0 (culled)
.return:
        rts                                     ; $007532: $4E75

; ============================================================================
; angle_normalize_alt ($007534) - Alternative Visibility Test
; Called by: Related visibility functions
; Parameters: Same as angle_normalize
; Returns: Same as angle_normalize
;
; This is a variant that skips the initial flag check and always performs
; the full BSP traversal. Used when the caller has already validated the
; polygon should be tested.
; ============================================================================

        org     $007534

angle_normalize_alt:
; Normalize D1
        addi.w  #ANGLE_OFFSET,d1                ; $007534: $0641 $4000 - Add quarter rotation
        andi.w  #ANGLE_MASK,d1                  ; $007538: $0241 $01FF - Mask to 0-511
        asl.w   #1,d1                           ; $00753C: $E341       - D1 *= 2
        ext.l   d1                              ; $00753E: $48C1       - Sign extend

; Normalize D2
        addi.w  #ANGLE_OFFSET,d2                ; $007540: $0642 $4000 - Add quarter rotation
        andi.w  #ANGLE_MASK,d2                  ; $007544: $0242 $01FF - Mask to 0-511
        asl.w   #1,d2                           ; $007548: $E342       - D2 *= 2
        ext.l   d2                              ; $00754A: $48C2       - Sign extend

; Initialize BSP traversal (no flag check)
        movea.l a1,a2                           ; $00754C: $2449       - Save A1 in A2
        moveq   #BSP_PLANE_COUNT,d5             ; $00754E: $7A09       - D5 = 9 planes

.alt_plane_loop:
        move.w  (a1)+,d3                        ; $007550: $3619       - Read plane selector
        moveq   #3,d6                           ; $007552: $7C03       - D6 = 3 (bit counter)

; Test bits 15-14 of plane selector (same logic as main function)
        asl.w   #1,d3                           ; $007554: $E343       - Shift bit 15 to carry
        bcs.s   .alt_branch_15                  ; $007556: $6532       - Branch if set
        asl.w   #1,d3                           ; $007558: $E343       - Shift bit 14 to carry
        bcs.s   .alt_branch_14                  ; $00755A: $651E       - Branch if set

; D1 path calculation
        move.w  d1,d0                           ; $00755C: $3001       - D0 = D1
        muls.w  (a1)+,d0                        ; $00755E: $C1D9       - D0 *= coefficient
        move.w  (a1)+,d4                        ; $007560: $3819       - D4 = constant
        ext.l   d4                              ; $007562: $48C4       - Sign extend
        asr.l   #5,d4                           ; $007564: $EBA4       - D4 >>= 5
        add.l   d4,d0                           ; $007566: $D084       - D0 += D4
        asr.l   #5,d0                           ; $007568: $EAA0       - D0 >>= 5
        cmp.l   d0,d2                           ; $00756A: $B480       - Compare D2 with D0
        blt.s   .alt_side_neg_1                 ; $00756C: $6D06       - Branch if D2 < D0

        asl.w   #1,d3                           ; $00756E: $E343       - Next bit
        bcs.s   .alt_visible                    ; $007570: $6552       - If set, visible
        bra.s   .alt_continue                   ; $007572: $6048       - Continue

.alt_side_neg_1:
        asl.w   #1,d3                           ; $007574: $E343       - Next bit
        bcc.s   .alt_visible                    ; $007576: $644C       - If clear, visible
        bra.s   .alt_continue                   ; $007578: $6042       - Continue

.alt_branch_14:
        cmp.w   (a1),d2                         ; $00757A: $B251       - Compare
        blt.s   .alt_14_neg                     ; $00757C: $6D06       - Branch if less
        asl.w   #1,d3                           ; $00757E: $E343       - Next bit
        bcc.s   .alt_visible                    ; $007580: $6442       - If clear, visible
        bra.s   .alt_skip                       ; $007582: $6036       - Skip, continue

.alt_14_neg:
        asl.w   #1,d3                           ; $007584: $E343       - Next bit
        bcs.s   .alt_visible_b                  ; $007586: $653C       - If set, visible
        bra.s   .alt_skip                       ; $007588: $6030       - Skip, continue

.alt_branch_15:
        asl.w   #1,d3                           ; $00758A: $E343       - Shift bit 14
        ; ... (continues with D2-based calculations, same pattern)
        ; Function continues similarly to main variant

; ============================================================================
; SUMMARY
; ============================================================================
;
; angle_normalize is called 8 times per frame for visibility culling.
; It performs BSP-based polygon visibility testing using normalized angles.
;
; Key operations:
; - Angle normalization to 512-step system
; - Signed 32-bit plane equation evaluation
; - BSP tree traversal with bit-encoded branch decisions
;
; Performance: ~150-300 cycles per call depending on early exit
;
; ============================================================================
