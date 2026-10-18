    #=============================================================================
    # painworld — src/screens/end.s
    # End-of-round screen: the frozen fight (so you see the spear land) with
    # the winner and the score on top. Enter starts the next round (inputs.s).
    #=============================================================================

    .include "constants.inc"

    .text
    .globl draw_end

end_title: .asciz "    P%ld WINS!    "
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
    call draw_spears

    # mvprintw(9, 31, end_title, winner + 1)
    movq $9, %rdi
    movq $31, %rsi
    movq $end_title, %rdx
    movq winner, %rcx
    incq %rcx                   # player 0 -> "P1"
    movq $0, %rax
    call mvprintw

    # mvprintw(11, 27, end_kills, kills[0], kills[1])
    movq $11, %rdi
    movq $27, %rsi
    movq $end_kills, %rdx
    movq kills, %rcx
    movq kills+8, %r8
    movq $0, %rax
    call mvprintw

    # mvprintw(13, 25, end_help)
    movq $13, %rdi
    movq $25, %rsi
    movq $end_help, %rdx
    movq $0, %rax
    call mvprintw

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
