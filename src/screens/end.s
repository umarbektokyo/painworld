    #=============================================================================
    # painworld — src/screens/end.s
    # End-of-round screen: the frozen fight (so you see the spear land) with
    # the winner and the score on top. Enter starts the next round (inputs.s).
    #=============================================================================

    .include "constants.inc"

    .text
    .globl draw_end

end_title: .asciz "    P%ld WINS!    "
end_draw:  .asciz "  DRAW: both drowned  "
end_kills: .asciz " kills  P1: %ld   P2: %ld "
end_help:  .asciz " Enter: next round   x: quit "

    #-----------------------------------------------------------------------------
    # void draw_end(void)
    #-----------------------------------------------------------------------------
draw_end:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    call draw_world             # the world, frozen (no update_physics)
    call draw_rain
    call draw_spears

    cmpq $0, winner             # winner -1 = nobody (both drowned)
    jl   .end_draw

    # mvprintw(15, 51, end_title, winner + 1)
    movq $15, %rdi
    movq $51, %rsi
    movq $end_title, %rdx
    movq winner, %rcx
    incq %rcx                   # player 0 -> "P1"
    movq $0, %rax
    call mvprintw
    jmp  .end_score

.end_draw:
    # mvprintw(15, 49, end_draw)
    movq $15, %rdi
    movq $49, %rsi
    movq $end_draw, %rdx
    movq $0, %rax
    call mvprintw

.end_score:
    # mvprintw(17, 47, end_kills, kills[0], kills[1])
    movq $17, %rdi
    movq $47, %rsi
    movq $end_kills, %rdx
    movq kills, %rcx
    movq kills+8, %r8
    movq $0, %rax
    call mvprintw

    # mvprintw(19, 45, end_help)
    movq $19, %rdi
    movq $45, %rsi
    movq $end_help, %rdx
    movq $0, %rax
    call mvprintw

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
