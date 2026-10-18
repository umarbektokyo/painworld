    #=============================================================================
    # painworld — src/screens/home.s
    # Home screen: the big title from the README + the menu.
    # The keys are handled in inputs.s.
    #
    # The title uses Unicode block characters, which is why main.s calls
    # setlocale() and we link with ncursesw (the "wide character" ncurses).
    # The strings are UTF-8: each block character is 3 bytes in memory, but one
    # cell on screen.
    #=============================================================================

    .include "constants.inc"

    .text
    .globl draw_home

splash_0: .asciz "                      ███                                                   ████      █████"
splash_1: .asciz "                     ▒▒▒                                                   ▒▒███     ▒▒███"
splash_2: .asciz " ████████   ██████   ████  ████████      █████ ███ █████  ██████  ████████  ▒███   ███████"
splash_3: .asciz "▒▒███▒▒███ ▒▒▒▒▒███ ▒▒███ ▒▒███▒▒███    ▒▒███ ▒███▒▒███  ███▒▒███▒▒███▒▒███ ▒███  ███▒▒███"
splash_4: .asciz " ▒███ ▒▒▒   ███████  ▒███  ▒███ ▒███     ▒███ ▒███ ▒███ ▒███ ▒███ ▒███ ▒▒▒  ▒███ ▒███ ▒███"
splash_5: .asciz " ▒███      ███▒▒███  ▒███  ▒███ ▒███     ▒▒███████████  ▒███ ▒███ ▒███      ▒███ ▒███ ▒███"
splash_6: .asciz " █████    ▒▒████████ █████ ████ █████     ▒▒████▒████   ▒▒██████  █████     █████▒▒████████"
splash_7: .asciz "▒▒▒▒▒      ▒▒▒▒▒▒▒▒ ▒▒▒▒▒ ▒▒▒▒ ▒▒▒▒▒       ▒▒▒▒ ▒▒▒▒     ▒▒▒▒▒▒  ▒▒▒▒▒     ▒▒▒▒▒  ▒▒▒▒▒▒▒▒"

splash:  .quad splash_0, splash_1, splash_2, splash_3, splash_4, splash_5, splash_6, splash_7
.equ SPLASH_COUNT, 8

home_text_0: .asciz "                it's like rain world, but made in assembly. thus, in pain."
home_text_1: .asciz ""
home_text_2: .asciz ""
home_text_3: .asciz "                                      Enter   start  "
home_text_4: .asciz "                                        g     guide  "
home_text_5: .asciz "                                        c     credits"
home_text_6: .asciz "                                        x     quit   "

home_text:  .quad home_text_0, home_text_1, home_text_2, home_text_3, home_text_4, home_text_5, home_text_6
.equ HOME_TEXT_COUNT, 7

    #-----------------------------------------------------------------------------
    # void draw_home(void)
    #-----------------------------------------------------------------------------
draw_home:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # attron(COLOR_PAIR(1)): the title in P1's yellow
    movq $1, %rdi
    shlq $8, %rdi               # COLOR_PAIR(n) is just n << 8
    call attron

    # draw_lines(splash, SPLASH_COUNT, 6, 14)       (91 wide, centred in 120)
    movq $splash, %rdi
    movq $SPLASH_COUNT, %rsi
    movq $6, %rdx
    movq $14, %rcx
    call draw_lines

    # attroff(COLOR_PAIR(1)): back to normal colours
    movq $1, %rdi
    shlq $8, %rdi
    call attroff

    # draw_lines(home_text, HOME_TEXT_COUNT, 16, 14)
    movq $home_text, %rdi
    movq $HOME_TEXT_COUNT, %rsi
    movq $16, %rdx
    movq $14, %rcx
    call draw_lines

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
