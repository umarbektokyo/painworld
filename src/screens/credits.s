    .text
    .globl draw_credits

credits_title_0: .asciz "               _ _ _"
credits_title_1: .asciz " __ _ _ ___ __| (_) |_ ___"
credits_title_2: .asciz "/ _| '_/ -_) _` | |  _(_-<"
credits_title_3: .asciz "\\__|_| \\___\\__,_|_|\\__/__/"

credits_title:  .quad credits_title_0, credits_title_1, credits_title_2, credits_title_3
.equ CREDITS_TITLE_COUNT, 4

credits_text_0: .asciz "              made by"
credits_text_1: .asciz ""
credits_text_2: .asciz "       Umarbek Bakhodirjonov ✨"
credits_text_3: .asciz "           Viesturs Kālis 🤯"
credits_text_4: .asciz "          Deniels Kruglovs 🥀"
credits_text_5: .asciz "          Gabriel Cancinos 🇦🇷"
credits_text_6: .asciz ""
credits_text_7: .asciz " inspired by Rain World (Videocult)"
credits_text_8: .asciz ""
credits_text_9: .asciz ""
credits_text_10: .asciz "        Enter: back to menu"

credits_text:  .quad credits_text_0, credits_text_1, credits_text_2, credits_text_3, credits_text_4, credits_text_5, credits_text_6, credits_text_7, credits_text_8, credits_text_9, credits_text_10
.equ CREDITS_TEXT_COUNT, 11

draw_credits:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # draw_lines(lines: credits_title, count: CREDITS_TITLE_COUNT, row: 8, col: 47)
    movq $credits_title, %rdi
    movq $CREDITS_TITLE_COUNT, %rsi
    movq $8, %rdx
    movq $47, %rcx
    call draw_lines

    # draw_lines(lines: credits_text, count: CREDITS_TEXT_COUNT, row: 14, col: 42)
    movq $credits_text, %rdi
    movq $CREDITS_TEXT_COUNT, %rsi
    movq $14, %rdx
    movq $42, %rcx
    call draw_lines

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
