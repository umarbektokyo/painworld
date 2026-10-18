    #=============================================================================
    # painworld — src/screens/home.s
    # Home screen: ASCII title + menu. The keys are handled in inputs.s.
    #=============================================================================

    .text
    .globl draw_home

title_0: .asciz "             _                         _     _"
title_1: .asciz " _ __   __ _(_)_ ____      _____  _ __| | __| |"
title_2: .asciz "| '_ \\ / _` | | '_ \\ \\ /\\ / / _ \\| '__| |/ _` |"
title_3: .asciz "| |_) | (_| | | | | \\ V  V / (_) | |  | | (_| |"
title_4: .asciz "| .__/ \\__,_|_|_| |_|\\_/\\_/ \\___/|_|  |_|\\__,_|"
title_5: .asciz "|_|"

title:  .quad title_0, title_1, title_2, title_3, title_4, title_5
.equ TITLE_COUNT, 6

home_text_0: .asciz "it's like rain world, but made in assembly. thus, in pain."
home_text_1: .asciz ""
home_text_2: .asciz ""
home_text_3: .asciz "            Enter   start"
home_text_4: .asciz "              g     guide"
home_text_5: .asciz "              c     credits"
home_text_6: .asciz "              x     quit"

home_text:  .quad home_text_0, home_text_1, home_text_2, home_text_3, home_text_4, home_text_5, home_text_6
.equ HOME_TEXT_COUNT, 7

    #-----------------------------------------------------------------------------
    # void draw_home(void)
    #-----------------------------------------------------------------------------
draw_home:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # draw_lines(title, TITLE_COUNT, 3, 16)
    movq $title, %rdi
    movq $TITLE_COUNT, %rsi
    movq $3, %rdx
    movq $16, %rcx
    call draw_lines

    # draw_lines(home_text, HOME_TEXT_COUNT, 10, 11)
    movq $home_text, %rdi
    movq $HOME_TEXT_COUNT, %rsi
    movq $10, %rdx
    movq $11, %rcx
    call draw_lines

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
