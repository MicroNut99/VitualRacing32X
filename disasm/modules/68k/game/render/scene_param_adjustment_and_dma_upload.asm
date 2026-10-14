; ============================================================================
; scene_param_adjustment_and_dma_upload — Scene Parameter Adjustment and DMA Upload
; ROM Range: $00DA90-$00DCAC (540 bytes)
; Data prefix (48 bytes: 6 longword pointers + 6 word pairs). Sends
; DMA transfer command, then loads viewport parameters from $FF2000
; table indexed by palette selection. Handles D-pad input for multi-
; axis camera/viewport adjustment with per-axis clamping. Writes
; updated parameters back to $FF2000. Sends SH2 update command and
; advances state counter.
;
; Uses: D0, D1, D3, D4, D5, A0, A1, A4
; Calls: $00E35A (sh2_send_cmd), $00E52C (dma_transfer),
;        $00DCAC/$00DCBE/$00DCB8/$00DCCA (increment/decrement helpers)
; Confidence: high
; ============================================================================

; --- Data prefix: 6 longword ROM pointers + 6 word pairs ---
; These are pointer/parameter table entries, decoded as instructions
; by the disassembler but are actually data.
scene_param_adjustment_and_dma_upload:
        MOVE.L  $6AE2(A1),D1                    ; $00DA90 ; data: ptr 0
        MOVE.L  -$7BF4(A1),D1                   ; $00DA94 ; data: ptr 1
        MOVE.L  -$5D12(A1),D1                   ; $00DA98 ; data: ptr 2
        MOVE.L  -$4608(A1),D1                   ; $00DA9C ; data: ptr 3
        MOVE.L  -$2CD4(A1),D1                   ; $00DAA0 ; data: ptr 4
        MOVE.L  $6AE2(A1),D1                    ; $00DAA4 ; data: ptr 5
        DC.W    $008B                           ; $00DAA8 ; data: param pair 0
        CMP.W  (A4)+,D3                         ; $00DAAA
        DC.W    $008B                           ; $00DAAC ; data: param pair 1
        EOR.W  D3,(A4)+                         ; $00DAAE
        DC.W    $008B                           ; $00DAB0 ; data: param pair 2
        CMP.W  (A4)+,D4                         ; $00DAB2
        DC.W    $008B                           ; $00DAB4 ; data: param pair 3
        EOR.W  D4,(A4)+                         ; $00DAB6
        DC.W    $008B                           ; $00DAB8 ; data: param pair 4
        CMP.W  (A4)+,D5                         ; $00DABA
        DC.W    $008B                           ; $00DABC ; data: param pair 5
        CMP.W  (A4)+,D3                         ; $00DABE

; --- Begin executable code ---
; Send DMA transfer of tile overlay data to SH2
        CLR.W  D0                               ; $00DAC0
        MOVE.B  (-24537).W,D0                   ; $00DAC2 ; offset flag
        jsr     MemoryInit(pc)          ; $4EBA $0A64
        MOVEA.L #$0603D100,A0                   ; $00DACA ; SH2 SDRAM dest
        MOVEA.L #$24004C58,A1                   ; $00DAD0 ; DMA source addr
        MOVE.W  #$0090,D0                       ; $00DAD6 ; length = 144 bytes
        MOVE.W  #$0010,D1                       ; $00DADA ; block size = 16
        DC.W    $6100,$087A         ; BSR.W  $00E35A; $00DADE ; sh2_send_cmd

; --- Load viewport params from table indexed by palette ---
        CLR.W  D0                               ; $00DAE2
        MOVE.B  (-24551).W,D0                   ; $00DAE4 ; main palette index
        TST.B  (-24537).W                       ; $00DAE8 ; alt palette active?
        BEQ.W  .palette_index_ready                        ; $00DAEC
        MOVE.B  (-24539).W,D0                   ; $00DAF0 ; use alt palette idx
.palette_index_ready:
; --- D0 * 10: compute table offset (5 words per entry) ---
        ADD.W   D0,D0                           ; $00DAF4 ; D0 *= 2
        MOVE.W  D0,D1                           ; $00DAF6 ; save D0*2
        ADD.W   D0,D0                           ; $00DAF8 ; D0 *= 4
        ADD.W   D0,D0                           ; $00DAFA ; D0 *= 8
        ADD.W   D1,D0                           ; $00DAFC ; D0 = orig*10
        LEA     $00FF2000,A0                    ; $00DAFE ; viewport param table
; --- Load 5 viewport parameters ---
        MOVE.W  $00(A0,D0.W),(-24550).W         ; $00DB04 ; X position
        MOVE.W  $02(A0,D0.W),(-24548).W         ; $00DB0A ; Y position
        MOVE.W  $04(A0,D0.W),(-24546).W         ; $00DB10 ; Z position (depth)
        MOVE.W  $06(A0,D0.W),(-24544).W         ; $00DB16 ; aux param A
        MOVE.W  $08(A0,D0.W),(-24542).W         ; $00DB1C ; aux param B

; --- Read D-pad input for camera adjustment ---
        MOVE.W  (-14226).W,D1                   ; $00DB22 ; read joypad state
        LSR.L  #8,D1                            ; $00DB26 ; shift to get D-pad
        BTST    #7,D1                           ; $00DB28 ; any D-pad pressed?
        BEQ.W  .write_back_params                        ; $00DB2C ; no input
        BTST    #5,D1                           ; $00DB30 ; C button = ext mode
        BNE.W  .extended_axis_mode                        ; $00DB34

; === Standard axis mode: D-pad adjusts X/Y/Z ===
; --- Y axis: Up (bit 0) ---
        BTST    #0,D1                           ; $00DB38 ; D-pad Up?
        BEQ.S  .check_y_dec                        ; $00DB3C
        MOVE.W  (-24548).W,D0                   ; $00DB3E ; load Y
        bsr.w   positive_velocity_step_small_inc; $6100 $0168
        CMPI.W  #$02F0,D0                       ; $00DB46 ; clamp max = 752
        BLT.W  .store_y_inc                        ; $00DB4A
        MOVE.W  #$02F0,D0                       ; $00DB4E
.store_y_inc:
        MOVE.W  D0,(-24548).W                   ; $00DB52 ; store Y
        BRA.W  .write_back_params                        ; $00DB56

; --- Y axis: Down (bit 1) ---
.check_y_dec:
        BTST    #1,D1                           ; $00DB5A ; D-pad Down?
        BEQ.S  .check_x_inc                        ; $00DB5E
        MOVE.W  (-24548).W,D0                   ; $00DB60 ; load Y
        bsr.w   negative_velocity_step_small_dec; $6100 $0158
        CMPI.W  #$FBFE,D0                       ; $00DB68 ; clamp min = -1026
        BGT.W  .store_y_dec                        ; $00DB6C
        MOVE.W  #$FBFE,D0                       ; $00DB70
.store_y_dec:
        MOVE.W  D0,(-24548).W                   ; $00DB74 ; store Y
        BRA.W  .write_back_params                        ; $00DB78

; --- X axis: Right (bit 3) ---
.check_x_inc:
        BTST    #3,D1                           ; $00DB7C ; D-pad Right?
        BEQ.S  .check_x_dec                        ; $00DB80
        MOVE.W  (-24550).W,D0                   ; $00DB82 ; load X
        bsr.w   positive_velocity_step_small_inc; $6100 $0124
        CMPI.W  #$0120,D0                       ; $00DB8A ; clamp max = 288
        BLT.W  .store_x_inc                        ; $00DB8E
        MOVE.W  #$0120,D0                       ; $00DB92
.store_x_inc:
        MOVE.W  D0,(-24550).W                   ; $00DB96 ; store X
        BRA.W  .write_back_params                        ; $00DB9A

; --- X axis: Left (bit 2) ---
.check_x_dec:
        BTST    #2,D1                           ; $00DB9E ; D-pad Left?
        BEQ.S  .check_z_inc                        ; $00DBA2
        MOVE.W  (-24550).W,D0                   ; $00DBA4 ; load X
        bsr.w   negative_velocity_step_small_dec; $6100 $0114
        CMPI.W  #$FEE0,D0                       ; $00DBAC ; clamp min = -288
        BGT.W  .store_x_dec                        ; $00DBB0
        MOVE.W  #$FEE0,D0                       ; $00DBB4
.store_x_dec:
        MOVE.W  D0,(-24550).W                   ; $00DBB8 ; store X
        BRA.W  .write_back_params                        ; $00DBBC

; --- Z axis: A button (bit 6) ---
.check_z_inc:
        BTST    #6,D1                           ; $00DBC0 ; A button?
        BEQ.S  .check_z_dec                        ; $00DBC4
        MOVE.W  (-24546).W,D0                   ; $00DBC6 ; load Z (depth)
        bsr.w   positive_velocity_step_small_inc; $6100 $00E0
        CMPI.W  #$0460,D0                       ; $00DBCE ; clamp max = 1120
        BLT.W  .store_z_inc                        ; $00DBD2
        MOVE.W  #$0460,D0                       ; $00DBD6
.store_z_inc:
        MOVE.W  D0,(-24546).W                   ; $00DBDA ; store Z
        BRA.W  .write_back_params                        ; $00DBDE

; --- Z axis: Start (bit 4) ---
.check_z_dec:
        BTST    #4,D1                           ; $00DBE2 ; Start button?
        BEQ.S  .write_back_params                        ; $00DBE6 ; no more axes
        MOVE.W  (-24546).W,D0                   ; $00DBE8 ; load Z
        bsr.w   negative_velocity_step_small_dec; $6100 $00D0
        CMPI.W  #$0050,D0                       ; $00DBF0 ; clamp min = 80
        BGT.W  .store_z_dec                        ; $00DBF4
        MOVE.W  #$0050,D0                       ; $00DBF8
.store_z_dec:
        MOVE.W  D0,(-24546).W                   ; $00DBFC ; store Z
        BRA.W  .write_back_params                        ; $00DC00

; === Extended axis mode (C+D-pad): adjusts aux params A/B ===
.extended_axis_mode:
; --- Aux A: Up (bit 0) ---
        BTST    #0,D1                           ; $00DC04 ; D-pad Up?
        BEQ.S  .check_ext_dec_a                        ; $00DC08
        MOVE.W  (-24544).W,D0                   ; $00DC0A ; load aux A
        bsr.w   positive_velocity_step_small_inc+12; $6100 $00A8 ; unclamped inc
        MOVE.W  D0,(-24544).W                   ; $00DC12 ; store aux A
        BRA.W  .write_back_params                        ; $00DC16

; --- Aux A: Down (bit 1) ---
.check_ext_dec_a:
        BTST    #1,D1                           ; $00DC1A ; D-pad Down?
        BEQ.S  .check_ext_inc_b                        ; $00DC1E
        MOVE.W  (-24544).W,D0                   ; $00DC20 ; load aux A
        bsr.w   negative_velocity_step_small_dec+12; $6100 $00A4 ; unclamped dec
        MOVE.W  D0,(-24544).W                   ; $00DC28 ; store aux A
        BRA.W  .write_back_params                        ; $00DC2C

; --- Aux B: Right (bit 3) ---
.check_ext_inc_b:
        BTST    #3,D1                           ; $00DC30 ; D-pad Right?
        BEQ.S  .check_ext_dec_b                        ; $00DC34
        MOVE.W  (-24542).W,D0                   ; $00DC36 ; load aux B
        bsr.w   positive_velocity_step_small_inc+12; $6100 $007C ; unclamped inc
        MOVE.W  D0,(-24542).W                   ; $00DC3E ; store aux B
        BRA.W  .write_back_params                        ; $00DC42

; --- Aux B: Left (bit 2) ---
.check_ext_dec_b:
        BTST    #2,D1                           ; $00DC46 ; D-pad Left?
        BEQ.S  .write_back_params                        ; $00DC4A ; no input
        MOVE.W  (-24542).W,D0                   ; $00DC4C ; load aux B
        bsr.w   negative_velocity_step_small_dec+12; $6100 $0078 ; unclamped dec
        MOVE.W  D0,(-24542).W                   ; $00DC54 ; store aux B
        BRA.W  .write_back_params                        ; $00DC58
        NOP                                     ; $00DC5C

; --- Write all 5 params back to table ---
.write_back_params:
        CLR.W  D0                               ; $00DC5E
        MOVE.B  (-24551).W,D0                   ; $00DC60 ; main palette idx
        TST.B  (-24537).W                       ; $00DC64 ; alt palette?
        BEQ.W  .writeback_index_ready                        ; $00DC68
        MOVE.B  (-24539).W,D0                   ; $00DC6C ; use alt idx
.writeback_index_ready:
; --- D0 * 10 for table offset ---
        ADD.W   D0,D0                           ; $00DC70 ; *= 2
        MOVE.W  D0,D1                           ; $00DC72 ; save
        ADD.W   D0,D0                           ; $00DC74 ; *= 4
        ADD.W   D0,D0                           ; $00DC76 ; *= 8
        ADD.W   D1,D0                           ; $00DC78 ; = orig*10
        LEA     $00FF2000,A0                    ; $00DC7A ; param table base
; --- Store 5 viewport params ---
        MOVE.W  (-24550).W,$00(A0,D0.W)         ; $00DC80 ; X position
        MOVE.W  (-24548).W,$02(A0,D0.W)         ; $00DC86 ; Y position
        MOVE.W  (-24546).W,$04(A0,D0.W)         ; $00DC8C ; Z position
        MOVE.W  (-24544).W,$06(A0,D0.W)         ; $00DC92 ; aux param A
        MOVE.W  (-24542).W,$08(A0,D0.W)         ; $00DC98 ; aux param B

; --- Send SH2 update + advance state ---
        MOVE.W  #$0020,$00FF0008                ; $00DC9E ; display timing
        ADDQ.W  #4,(-14210).W                   ; $00DCA6 ; advance state counter
        RTS                                     ; $00DCAA
