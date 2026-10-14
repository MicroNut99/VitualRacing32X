; ============================================================================
; Code Section ($022200-$0241FF)
; Generated from ROM bytes - guaranteed accurate
; ============================================================================

        org     $022200

        ROMDATA $022200,$02300A
; ═══════════════════════════════════════════════════════════════════════════
; data_copy: Matrix/Constant Data Copy (26 bytes, $02300A-$023023)
; Source: disasm/sh2/3d_engine/data_copy.asm
; Purpose: Copy 12 longwords (48 bytes) from R13 source to fixed dst 0xC0000740
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/data_copy.inc"
; ═══════════════════════════════════════════════════════════════════════════
; main_coordinator_short: Main Coordinator / Switch Dispatcher (76 bytes, $023024-$02306F)
; Source: disasm/sh2/3d_engine/main_coordinator_short.asm
; Purpose: Central dispatch for 3D engine, dual entry points, jump table
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/main_coordinator_short.inc"
; ═══════════════════════════════════════════════════════════════════════════
; case_handlers_short: Switch Case Handlers Block (88 bytes, $023070-$0230C7)
; Source: disasm/sh2/3d_engine/case_handlers_short.asm
; Purpose: Case handlers for main_coordinator_short jump table (cases 0/2/4/6)
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/case_handlers_short.inc"
; ═══════════════════════════════════════════════════════════════════════════
; case_handlers_short exit paths + func_003 + func_004 (32 bytes, $0230C8-$0230E7)
; Source: disasm/sh2/3d_engine/offset_copy_short.asm
; Purpose: Offset-based data copy utilities
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/offset_copy_short.inc"
; ═══════════════════════════════════════════════════════════════════════════
; transform_loop: Matrix Transform Loop (56 bytes, $0230E8-$02311F)
; Source: disasm/sh2/3d_engine/transform_loop.asm
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/transform_loop.inc"
; ═══════════════════════════════════════════════════════════════════════════
; matrix_multiply: Matrix × Vector Multiplication (88 bytes, $023120-$023177)
; Source: disasm/sh2/3d_engine/matrix_multiply.asm
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/matrix_multiply.inc"
; ═══════════════════════════════════════════════════════════════════════════
; alt_transform_loop: Alt Transform Loop (52 bytes, $023178-$0231AB)
; Source: disasm/sh2/3d_engine/alt_transform_loop.asm
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/alt_transform_loop.inc"
; ═══════════════════════════════════════════════════════════════════════════
; alt_matrix_multiply: Alt Matrix × Vector Multiplication (56 bytes, $0231AC-$0231E3)
; Source: disasm/sh2/3d_engine/alt_matrix_multiply.asm
; NOTE: Delay slot (0x81A7) provided by display_list_4elem's first instruction
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/alt_matrix_multiply.inc"
; ═══════════════════════════════════════════════════════════════════════════
; display_list_4elem: Display List Handler Type A (30 bytes, $0231E4-$023201)
; Source: disasm/sh2/3d_engine/display_list_4elem.asm
; NOTE: First instruction (0x81A7) serves as alt_matrix_multiply's delay slot
; NOTE: RTS delay slot (0x81E3) provided by display_list_3elem's first instruction
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/display_list_4elem.inc"
; ═══════════════════════════════════════════════════════════════════════════
; display_list_3elem: Display List Handler Type B (26 bytes, $023202-$02321B)
; Source: disasm/sh2/3d_engine/display_list_3elem.asm
; NOTE: First instruction (0x81E3) serves as display_list_4elem's delay slot
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/display_list_3elem.inc"
        dc.w    $81E3        ; $02321C ; display_list_3elem delay slot (borrowed from next)
        ROMDATA $02321E,$023220
; display_list_loop: Display List Processing Loop (84 bytes)
; ROM offset: $023220-$023273
        include "sh2/generated/display_list_loop.inc"
; Literal pool entry between display_list_loop and display_entry
        ROMDATA $023274,$023278
; ═══════════════════════════════════════════════════════════════════════════
; display_entry: Display Entry Handler (92 bytes, $023278-$0232D3)
; Source: disasm/sh2/3d_engine/display_entry.asm
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/display_entry.inc"
; ═══════════════════════════════════════════════════════════════════════════
; vdp_init_short: VDP Init / Data Table Copy (92 bytes, $0232D4-$02332F)
; Source: disasm/sh2/3d_engine/vdp_init_short.asm
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/vdp_init_short.inc"
; func_014 + func_015: VDP Data Copy Utilities (56 bytes: $023330-$023367)
; func_014: 6-byte copy to VDP registers, func_015: 402-byte bulk frame copy
        include "sh2/generated/vdp_copy_short.inc"
; coord_transform: Coordinate Transformation Utility (34 bytes, $023368-$02338A)
; HOTSPOT: Called 4× per polygon (67,200 cycles/frame)
        include "sh2/generated/coord_transform.inc"
; quad_helper: JMP trampoline to expansion ROM (26 bytes, $02338A-$0233A3)
; S-6 Phase B: Redirects to relocated state machine at $301300
        include "sh2/generated/quad_helper.inc"
; quad_batch_short: JMP trampolines to expansion ROM (112 bytes: $0233A4-$023413)
; S-6 Phase B: Two entries → expansion $301336 (main) and $30138C (alt path)
        include "sh2/generated/quad_batch_short.inc"
; quad_batch_alt_short: JMP trampolines to expansion ROM (starts at $023414)
; S-6 Phase B: Three entries → expansion $3013CA, $30140A, $301440
        include "sh2/generated/quad_batch_alt_short.inc"
; vertex_helper_short: Vertex processor helper (starts at $0234A0)
; Called by quad_batch_short/quad_batch_alt_short for vertex processing loop
        include "sh2/generated/vertex_helper_short.inc"
; vertex_transform: JMP trampoline to expansion ROM (starts at $0234C8)
; S-6: Redirects to vertex_transform_optimized at $3011E0 (coord_transform inlined)
; Saves ~4,800 cycles/frame by eliminating BSR/RTS overhead for coord_transform
        include "sh2/generated/vertex_transform_orig.inc"
; ═══════════════════════════════════════════════════════════════════════════
; wait_ready: Wait for Ready / Hardware Sync (26 bytes, $0234EE-$023507)
; Source: disasm/sh2/3d_engine/wait_ready.asm
; Purpose: Polls hardware status waiting for bit 3 to be set
; ═══════════════════════════════════════════════════════════════════════════
        include "sh2/generated/wait_ready.inc"
; frustum_cull_short: Frustum Culling / Visibility Dispatcher (238 bytes: $023508-$0235F5)
; Core visibility testing hub - coordinates all frustum culling
; Calls: screen_coords_short, bounds_compare_short, func_029, scanline_setup, render_quad_short, render_dispatch_short
        include "sh2/generated/frustum_cull_short.inc"
; screen_coords_short: Screen Coordinate Calculator (62 bytes: $0235F6-$023633)
; Calculates screen-space coordinates for quad vertices
        include "sh2/generated/screen_coords_short.inc"
; coord_offset_short: Coordinate offset calculator (16 bytes: $023634-$023643)
; Calculates coordinate offsets from input buffer
        include "sh2/generated/coord_offset_short.inc"
; bounds_compare_short, func_027, func_028 (68 bytes: $023644-$023687)
; Bounds comparison with shared exit paths
        include "sh2/generated/bounds_compare_short.inc"
; func_029, func_030, func_031 (82 bytes: $023688-$0236D9)
; Visibility edge classifier with shared exit paths
        include "sh2/generated/visibility_short.inc"
; scanline_setup: Table Lookup / Indexed Load Loop (32 bytes, $0236DA-$0236F9)
; Uses indexed addressing @(R0,R8) for table lookups
        include "sh2/generated/scanline_setup.inc"
; render_quad_short: Quad Rendering / Edge Walking (98 bytes: $0236FA-$02375B)
; Edge walking algorithm for polygon rasterization, calls span_filler_short
        include "sh2/generated/render_quad_short.inc"
; span_filler_short: Span Filler / Edge Interpolation (122 bytes: $02375C-$0237D5)
; Bresenham-style edge interpolation with reciprocal table for fast division
        include "sh2/generated/span_filler_short.inc"
; render_dispatch_short: Render Dispatch D (72 bytes: $0237D6-$02381D)
; Display list processor for polygon entries
        include "sh2/generated/render_dispatch_short.inc"
; helpers_short: Visibility Helper Functions (64 bytes: $02381E-$02385D)
; Helper subroutines for render_dispatch_short render dispatch
        include "sh2/generated/helpers_short.inc"
; display_list_short: Display List Buffer Setup (122 bytes: $02385E-$0238D7)
; Initializes VDP display list buffers, jump table dispatch
        include "sh2/generated/display_list_short.inc"
; display_cases_short: Jump Table Case Handlers (212 bytes: $0238D8-$0239AB)
; Case handlers for display_list_short's 12-entry jump table
        include "sh2/generated/display_cases_short.inc"
; Padding/unused at $0239AC
        dc.w    $BFFF        ; $0239AC  ; Mask constant (0xBFFF)
        dc.w    $0009        ; $0239AE  ; NOP padding
; display_utility_short: Data Copy and GBR Setup (28 bytes: $0239B0-$0239CB)
; Small utility called by render_coord_short to copy data and set up GBR
        include "sh2/generated/display_utility_short.inc"
; Literal pool for display_utility_short (data: $0239CC-$0239EF)
        ROMDATA $0239CC,$0239F0
; render_coord_short: Main Render Coordinator (98 bytes: $0239F0-$023A51)
; Coordinates render pipeline: init, data copy, GBR setup, status checks
        include "sh2/generated/render_coord_short.inc"
; data_copy_util_short: VDP Data Copy Helper (20 bytes: $023A52-$023A65)
; Small utility that copies data from source to destination
        include "sh2/generated/data_copy_util_short.inc"
; Literal pool for data_copy_util_short (data: $023A66-$023A6F)
        dc.w    $0091        ; $023A66  ; Loop count (145)
        ROMDATA $023A68,$023A70
; polygon_batch_short: Polygon Batch Processor (312 bytes: $023A70-$023BA7)
; Core polygon batch processing with vertex interpolation and edge calculations
        include "sh2/generated/polygon_batch_short.inc"
; edge_scan_short: Edge/Scan Processor (268 bytes: $023BA8-$023CB3)
; Edge and scanline processing with multiple entry points
        include "sh2/generated/edge_scan_short.inc"
; dispatch_loop_short: Dispatch Loop Processor (68 bytes: $023CB4-$023CF7)
; BSRF-based dispatch loop with jump table for entry type handling
        include "sh2/generated/dispatch_loop_short.inc"
; array_copy_short: Array Copy with Stride (36 bytes: $023CF8-$023D1B)
; Nested loop copies longword pairs with stride advance
        include "sh2/generated/array_copy_short.inc"
; Literal pool (shared by dispatch_loop_short): stride and table base
        dc.w    $0200        ; $023D1C stride constant
        ROMDATA $023D1E,$023D24
; bounds_check_short: Bounds Check Handler Type 10 (26 bytes: $023D24-$023D3D)
; Checks bounds and jumps to array_copy_short inner loop
        include "sh2/generated/bounds_check_short.inc"
; bounds_handler_short: Bounds Check Handler Type 7 (22 bytes: $023D3E-$023D53)
; Checks bounds and jumps to $023FCA
        include "sh2/generated/bounds_handler_short.inc"
; bounds_entry_short: Bounds Check Entry Type 8 (26 bytes: $023D54-$023D6D)
; Saves PR in delay slot, enters multi_bsr_short body
        include "sh2/generated/bounds_entry_short.inc"
; multi_bsr_short: Multi-BSR Processing Handler (88 bytes: $023D6E-$023DC5)
; 10 BSR calls to processing subroutine at $023ED0
        include "sh2/generated/multi_bsr_short.inc"
; Literal pool for multi_bsr_short (addresses for MOV.L)
        ROMDATA $023DC6,$023DD8
; offset_bsr_short: Offset Multi-BSR Handler Type 3 (92 bytes: $023DD8-$023E33)
; Adds offset to dest, 10 BSR calls to $023F2E
        include "sh2/generated/offset_bsr_short.inc"
; Literal pool for offset_bsr_short (offset and addresses)
        ROMDATA $023E34,$023E48
; small_bsr_short: Small BSR Handler Types 4/5 (22 bytes: $023E48-$023E5D)
; 2 BSR calls to $023F2E
        include "sh2/generated/small_bsr_short.inc"
; Literal pool for small_bsr_short (address)
        ROMDATA $023E5E,$023E64
; offset_small_short: Offset Small BSR Handler Type 6 (38 bytes: $023E64-$023E89)
; Adds offset, conditional skip, 2 BSR calls
        include "sh2/generated/offset_small_short.inc"
; Literal pool for offset_small_short (offset and address)
        ROMDATA $023E8A,$023E90
; conditional_bsr_short: Conditional BSR Handler Type 9 (56 bytes: $023E90-$023EC7)
; Uses R12 flag for conditional BSR calls
        include "sh2/generated/conditional_bsr_short.inc"
; Literal pool for conditional_bsr_short (offset and address constants)
        dc.w    $0400        ; $023EC8: offset constant
        ROMDATA $023ECA,$023ECC
        dc.w    $0600        ; $023ECC: address constant
        ROMDATA $023ECE,$023ED0
; unrolled_copy_short: Unrolled 8-Block Copy with Stride (92 bytes: $023ED0-$023F2B)
; Called by multi_bsr_short's 10 BSR calls. Copies 64 bytes with stride.
; Note: RTS delay slot at $023F2C is shared with unrolled_data_copy (first NOP)
        include "sh2/generated/unrolled_copy_short.inc"
; ============================================================================
; unrolled_data_copy: Unrolled Data Copy Loop (HOTSPOT: 4× by func_060-063)
; SH2 Address: $02223F2C | ROM: $23F2C | 152 bytes
; Copies 14 × 8 = 112 bytes with custom stride
; Source: disasm/sh2/3d_engine/unrolled_data_copy.asm
; ============================================================================
        include "disasm/sh2/generated/unrolled_data_copy.inc"
; ============================================================================
; rle_decoder: Run-Length Decoder (leaf function)
; SH2 Address: $02223FC4 | ROM: $23FC4 | 48 bytes
; Decodes RLE data: (value:count) pairs written to buffer
; Note: First NOP is shared delay slot from unrolled_data_copy
; Source: disasm/sh2/3d_engine/rle_decoder.asm
; ============================================================================
        include "disasm/sh2/generated/rle_decoder.inc"
; ============================================================================
; rle_entry_alt1_short: RLE Entry Point (Alternative 1) (14 bytes: $023FF4-$024001)
; Setup + BRA into rle_decoder loop with NEG R13,R13 in delay slot
; ============================================================================
        include "sh2/generated/rle_entry_alt1_short.inc"
; ============================================================================
; rle_entry_alt2_short: RLE Entry Point (Alternative 2) (12 bytes: $024002-$02400D)
; Setup + BRA into rle_decoder loop
; ============================================================================
        include "sh2/generated/rle_entry_alt2_short.inc"
; ============================================================================
; block_copy_stride_short: Block Copy with Stride (76 bytes: $02400E-$024059)
; Nested loop block copy with bounds checking
; ============================================================================
        include "sh2/generated/block_copy_stride_short.inc"
; Literal pool for block_copy_stride_short
        dc.w    $01FF        ; $02405A: mask constant
        dc.w    $0140        ; $02405C: threshold (320)
        dc.w    $FFFF        ; $02405E: sentinel
; ============================================================================
; loop_dispatcher_short: Loop Dispatcher (36 bytes: $024060-$024083)
; Iterates through elements calling setup and process subroutines
; ============================================================================
        include "sh2/generated/loop_dispatcher_short.inc"
; ============================================================================
; context_setup_short: Context Setup / Parameter Initialization (122 bytes: $024084-$0240FD)
; Initializes rendering context from R14 structure, formats display data
; Called by loop_dispatcher_short via BSR. Note: $001E = MOV.L @(R0,R1),R0 (indexed load)
; ============================================================================
        include "sh2/generated/context_setup_short.inc"
; Literal pool for context_setup_short
        dc.w    $0000        ; $0240FE: padding
        dc.w    $C000        ; $024100: VDP base high word
        dc.w    $0000        ; $024102: VDP base low word ($C0000000)
        dc.w    $0600        ; $024104: table 1 high word
        dc.w    $410C        ; $024106: table 1 low word ($0600410C)
        dc.w    $0600        ; $024108: table 2 high word
        dc.w    $4184        ; $02410A: table 2 low word ($06004184)
        ROMDATA $02410C,$0241A4
; ============================================================================
; element_processor_short: Element Processor with BSR Loop (42 bytes: $0241A4-$0241CD)
; Processes display elements, calls BSR based on element value comparison
; ============================================================================
        include "sh2/generated/element_processor_short.inc"
; Literal pool for element_processor_short (data: $0241CE-$0241D7)
        ROMDATA $0241CE,$0241D8
; ============================================================================
; negative_handler_short: Negative Element Handler (16 bytes: $0241D8-$0241E7)
; Called when element value is negative; sets up registers and jumps to loop
; ============================================================================
        include "sh2/generated/negative_handler_short.inc"
; ============================================================================
; block_copy_14_short: Block Copy 14 (30 bytes: $0241E8-$024205)
; Copies 14 blocks of 8 bytes using table base lookup
; Note: Crosses section boundary at $024200 into code_24200
; ============================================================================
        include "sh2/generated/block_copy_14_short.inc"
