# guide.s - how to play

    .text
    .globl draw_guide

guide_title_0: .asciz "           _    _"
guide_title_1: .asciz " __ _ _  _(_)__| |___"
guide_title_2: .asciz "/ _` | || | / _` / -_)"
guide_title_3: .asciz "\\__, |\\_,_|_\\__,_\\___|"
guide_title_4: .asciz "|___/"

guide_title:  .quad guide_title_0, guide_title_1, guide_title_2, guide_title_3, guide_title_4
.equ GUIDE_TITLE_COUNT, 5

guide_text_0: .asciz "GOAL    Spear the other slugcat before the flood drowns you both."
guide_text_1: .asciz ""
guide_text_2: .asciz "        P1 (green)           P2 (orange)"
guide_text_3: .asciz "run     a / d                left / right"
guide_text_4: .asciz "jump    w                    up"
guide_text_5: .asciz "stop    s                    down"
guide_text_6: .asciz "spear   q                    ."
guide_text_7: .asciz ""
guide_text_8: .asciz "SPEARS  Walk onto a spear and press your spear key to pick it up."
guide_text_9: .asciz "        Press it again to throw it the way you are facing."
guide_text_10: .asciz "RAIN    Drops on dry floor vanish, but rain landing on rain stays."
guide_text_11: .asciz "        It rains harder and harder. Head under water = drowned."
guide_text_12: .asciz "        Both drown at the same time = draw."
guide_text_13: .asciz ""
guide_text_14: .asciz "                       Enter: back to menu"

guide_text:  .quad guide_text_0, guide_text_1, guide_text_2, guide_text_3, guide_text_4, guide_text_5, guide_text_6, guide_text_7, guide_text_8, guide_text_9, guide_text_10, guide_text_11, guide_text_12, guide_text_13, guide_text_14
.equ GUIDE_TEXT_COUNT, 15

draw_guide:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # draw_lines(guide_title, GUIDE_TITLE_COUNT, 7, 49)
    movq $guide_title, %rdi
    movq $GUIDE_TITLE_COUNT, %rsi
    movq $7, %rdx
    movq $49, %rcx
    call draw_lines

    # draw_lines(guide_text, GUIDE_TEXT_COUNT, 13, 26)
    movq $guide_text, %rdi
    movq $GUIDE_TEXT_COUNT, %rsi
    movq $13, %rdx
    movq $26, %rcx
    call draw_lines

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
