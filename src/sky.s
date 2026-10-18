# sky.s - the sky "shader"
#
# runs for every empty cell and says how cloudy that spot is right now (0, 1, 2).
# like a fragment shader it only knows its position (col, row) and the time
# (frame_count). three sine waves drifting at different speeds + "more clouds
# at the top" = slow storm clouds.
# no floats: sin comes from a 64 byte table (one full wave, -8..8). i & 63 wraps
# any index around, even negative ones (two's complement keeps the low bits).

    .include "constants.inc"

    .text
    .globl sky_shade

sine:
    .byte   0,   1,   2,   2,   3,   4,   4,   5,   6,   6,   7,   7,   7,   8,   8,   8
    .byte   8,   8,   8,   8,   7,   7,   7,   6,   6,   5,   4,   4,   3,   2,   2,   1
    .byte   0,  -1,  -2,  -2,  -3,  -4,  -4,  -5,  -6,  -6,  -7,  -7,  -7,  -8,  -8,  -8
    .byte  -8,  -8,  -8,  -8,  -7,  -7,  -7,  -6,  -6,  -5,  -4,  -4,  -3,  -2,  -2,  -1

# long sky_shade(long col /* %rdi */, long row /* %rsi */) -> %rax
#   v  = sine[(col + t/8) & 63]                    big slow wave
#   v += sine[(col*3 - row*4 - t/4) & 63]          diagonal, other direction
#   v += sine[(row*5 + col + col/4 + t/16) & 63]   very slow
#   v += SKY_BIAS_ROW - row                        cloudy up top, clear below
#   2 if v > SKY_THICK, 1 if v > SKY_THIN, else 0
# (waves repeat every 64, ~21 and ~51 cols, so no visible pattern across 120)
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
    movsbq sine(%rax), %r9      # r9 = v, movsbq sign-extends the byte

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
