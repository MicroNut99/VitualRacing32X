        .section .text
        .align 2
        .global batch_copy_handler

batch_copy_handler:
        mov.l   comm_base, r8      ! r8 = 0x20004020
        mov.l   @(8,r8), r4        ! r4 = COMM4 (table address)

        mov.w   @r4, r5            ! r5 = count (16-bit)
        extu.w  r5, r5             ! zero-extend
        add     #4, r4             ! skip count + padding

        tst     r5, r5
        bt      .done

.copy_loop:
        mov.l   @r4+, r1           ! r1 = src
        mov.l   @r4+, r2           ! r2 = dst
        mov.l   @r4+, r3           ! r3 = size (bytes)
        shlr2   r3                 ! r3 = size / 4 (longwords)

        tst     r3, r3
        bt      .next_entry

.inner_copy:
        mov.l   @r1+, r0           ! read longword
        mov.l   r0, @r2            ! write longword
        add     #4, r2
        dt      r3
        bf      .inner_copy

.next_entry:
        dt      r5
        bf      .copy_loop

.done:
        mov     #0, r0
        mov.w   r0, @(12, r8)      ! COMM6 = 0 (done)
        mov.b   r0, @r8            ! COMM0 = 0 (ready)
        rts
        nop

        .align 2
comm_base:
        .long   0x20004020
