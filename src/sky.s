    #=============================================================================
    # painworld — src/sky.s
    # The sky "shader": a tiny function that is run for every empty cell and
    # returns how cloudy that spot of sky is right now (0, 1 or 2).
    #
    # Like a fragment shader, it only looks at its position (col, row) and the
    # time (frame_count). It adds three sine waves that drift at different
    # speeds and directions, plus a bias that makes the top of the screen more
    # cloudy. Where the sum is big we draw a dim cloud: slow storm clouds.
    #
    # No floats: sin() comes from a table of 64 bytes, one full wave, values
    # -8..8. sine[i & 63] wraps around, so any index works (even negative ones,
    # because & 63 keeps the low 6 bits of a two's complement number).
    #=============================================================================

    .include "constants.inc"

    .text
    .globl sky_shade

sine:
    .byte   0,   1,   2,   2,   3,   4,   4,   5,   6,   6,   7,   7,   7,   8,   8,   8
    .byte   8,   8,   8,   8,   7,   7,   7,   6,   6,   5,   4,   4,   3,   2,   2,   1
    .byte   0,  -1,  -2,  -2,  -3,  -4,  -4,  -5,  -6,  -6,  -7,  -7,  -7,  -8,  -8,  -8
    .byte  -8,  -8,  -8,  -8,  -7,  -7,  -7,  -6,  -6,  -5,  -4,  -4,  -3,  -2,  -2,  -1

    #-----------------------------------------------------------------------------
    # long sky_shade(long col /* %rdi */, long row /* %rsi */) -> %rax
    #
    #   t = frame_count
    #   v  = sine[(col + t/8) & 63]                     big slow wave
    #   v += sine[(col*3 - row*4 - t/4) & 63]           diagonal, the other way
    #   v += sine[(row*5 + col + col/4 + t/16) & 63]    very slow, mostly vertical
    #   v += SKY_BIAS_ROW - row                         cloudy at the top, clear
    #                                                   lower down
    # (the three waves repeat every 64, ~21 and ~51 columns, so together they
    #  don't visibly repeat across the 120 columns)
    #   return 2 if v > SKY_THICK, 1 if v > SKY_THIN, else 0
    #-----------------------------------------------------------------------------
sky_shade:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq frame_count, %r8       # r8 = t

    # v = sine[(col + t/8) & 63]
    movq %r8, %rax
    shrq $3, %rax               # t / 8
    addq %rdi, %rax
    andq $63, %rax
    movsbq sine(%rax), %r9      # r9 = v  (movsbq: sign-extend the byte)

    # v += sine[(col*3 - row*4 - t/4) & 63]
    movq %rdi, %rax
    imulq $3, %rax
    movq %rsi, %rcx
    imulq $4, %rcx
    subq %rcx, %rax
    movq %r8, %rcx
    shrq $2, %rcx               # t / 4
    subq %rcx, %rax
    andq $63, %rax
    movsbq sine(%rax), %rax
    addq %rax, %r9

    # v += sine[(row*5 + col + col/4 + t/16) & 63]
    movq %rsi, %rax
    imulq $5, %rax
    addq %rdi, %rax
    movq %rdi, %rcx
    shrq $2, %rcx               # col / 4
    addq %rcx, %rax
    movq %r8, %rcx
    shrq $4, %rcx               # t / 16
    addq %rcx, %rax
    andq $63, %rax
    movsbq sine(%rax), %rax
    addq %rax, %r9

    # v += SKY_BIAS_ROW - row
    movq $SKY_BIAS_ROW, %rax
    subq %rsi, %rax
    addq %rax, %r9

    # v -> 0, 1 or 2
    movq $2, %rax
    cmpq $SKY_THICK, %r9
    jg   .sky_done
    movq $1, %rax
    cmpq $SKY_THIN, %r9
    jg   .sky_done
    movq $0, %rax

.sky_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
