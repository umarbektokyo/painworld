# fights.s - drawing the fight: world, rain, spears, then the score on top

    .include "constants.inc"

    .text
    .globl draw_game

hud_text: .asciz " %ld - %ld "

draw_game:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    call draw_world             # render.s (platforms, water, slugcats, sky)
    call draw_rain              # rain.s
    call draw_spears            # spears.s

    movq $0, %rdi               # mvprintw(0, 56, hud_text, kills[0], kills[1])
    movq $56, %rsi
    movq $hud_text, %rdx
    movq kills, %rcx
    movq kills+8, %r8           # kills[1] is 8 bytes after kills[0]
    movq $0, %rax               # no float args, like printf
    call mvprintw

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
