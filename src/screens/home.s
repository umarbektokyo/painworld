# home.s - title (the one from the README) + menu, keys are in inputs.s
# the title is unicode blocks, so it's UTF-8: 3 bytes per block in memory,
# 1 cell on screen. that's why main.s calls setlocale and we link ncursesw.

    .include "constants.inc"

    .text
    .globl draw_home

splash_0: .asciz "   ▄███████▄    ▄████████  ▄█  ███▄▄▄▄         ▄█     █▄   ▄██████▄     ▄████████  ▄█       ████████▄"
splash_1: .asciz "  ███    ███   ███    ███ ███  ███▀▀▀██▄      ███     ███ ███    ███   ███    ███ ███       ███   ▀███"
splash_2: .asciz "  ███    ███   ███    ███ ███▌ ███   ███      ███     ███ ███    ███   ███    ███ ███       ███    ███"
splash_3: .asciz "  ███    ███   ███    ███ ███▌ ███   ███      ███     ███ ███    ███  ▄███▄▄▄▄██▀ ███       ███    ███"
splash_4: .asciz "▀█████████▀  ▀███████████ ███▌ ███   ███      ███     ███ ███    ███ ▀▀███▀▀▀▀▀   ███       ███    ███"
splash_5: .asciz "  ███          ███    ███ ███  ███   ███      ███     ███ ███    ███ ▀███████████ ███       ███    ███"
splash_6: .asciz "  ███          ███    ███ ███  ███   ███      ███ ▄█▄ ███ ███    ███   ███    ███ ███▌    ▄ ███   ▄███"
splash_7: .asciz " ▄████▀        ███    █▀  █▀    ▀█   █▀        ▀███▀███▀   ▀██████▀    ███    ███ █████▄▄██ ████████▀"
splash_8: .asciz "                                                                       ███    ███ ▀"

splash:  .quad splash_0, splash_1, splash_2, splash_3, splash_4, splash_5, splash_6, splash_7, splash_8
.equ SPLASH_COUNT, 9

home_text_0: .asciz "                it's like rain world, but made in assembly. thus, in pain."
home_text_1: .asciz ""
home_text_2: .asciz ""
home_text_3: .asciz "                                      Enter   start  "
home_text_4: .asciz "                                        g     guide  "
home_text_5: .asciz "                                        c     credits"
home_text_6: .asciz "                                        x     quit   "

home_text:  .quad home_text_0, home_text_1, home_text_2, home_text_3, home_text_4, home_text_5, home_text_6
.equ HOME_TEXT_COUNT, 7

draw_home:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # attron(attrs: COLOR_PAIR(1)), title in P1's green
    movq $1, %rdi
    shlq $8, %rdi               # COLOR_PAIR(n) is just n << 8
    call attron

    # draw_lines(lines: splash, count: SPLASH_COUNT, row: 5, col: 8)
    # (103 wide, so col 8 centres it in 120)
    movq $splash, %rdi
    movq $SPLASH_COUNT, %rsi
    movq $5, %rdx
    movq $8, %rcx
    call draw_lines

    # attroff(attrs: COLOR_PAIR(1))
    movq $1, %rdi
    shlq $8, %rdi
    call attroff

    # draw_lines(lines: home_text, count: HOME_TEXT_COUNT, row: 16, col: 14)
    movq $home_text, %rdi
    movq $HOME_TEXT_COUNT, %rsi
    movq $16, %rdx
    movq $14, %rcx
    call draw_lines

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
