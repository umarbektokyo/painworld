# inputs.s - keys -> player actions and scene changes
#
# terminals only say "a key was typed", never "released". so a move key sets
# move_timer = KEY_HOLD and you keep running while it's > 0. holding the key
# auto-repeats, which keeps refilling it.
#
#   P1: a/d run, w jump, s stop, q spear      P2: arrows, . spear
#   Enter: start / next round / back      g, c: guide, credits      x, Esc: quit

    .include "constants.inc"

    .text
    .globl poll_input

# void poll_input(void)
# reads keys until getch says there are none left (-1).
# %rcx = which player the key belongs to, so both players share the same code.
poll_input:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = current key
    subq  $8, %rsp              # stack aligned to 16 for getch

.read_key:
    call getch                  # eax = key, -1 = nothing
    cmpl $-1, %eax
    je   .no_more_keys
    movl %eax, %ebx

    cmpq $'x', %rbx
    je   .quit
    cmpq $KEY_ESC, %rbx
    je   .quit
    cmpq $KEY_NEWLINE, %rbx     # Enter
    je   .enter
    cmpq $'g', %rbx
    je   .guide
    cmpq $'c', %rbx
    je   .credits

    # P1
    movq $0, %rcx
    cmpq $'a', %rbx
    je   .move_left
    cmpq $'d', %rbx
    je   .move_right
    cmpq $'w', %rbx
    je   .jump
    cmpq $'s', %rbx
    je   .stop
    cmpq $'q', %rbx
    je   .grab

    # P2
    movq $1, %rcx
    cmpq $KEY_LEFT, %rbx
    je   .move_left
    cmpq $KEY_RIGHT, %rbx
    je   .move_right
    cmpq $KEY_UP, %rbx
    je   .jump
    cmpq $KEY_DOWN, %rbx
    je   .stop
    cmpq $'.', %rbx
    je   .grab

    jmp  .read_key              # some other key, ignore

.move_left:
    movq $-1, move_dir(,%rcx,8)
    movq $KEY_HOLD, move_timer(,%rcx,8)
    jmp  .read_key

.move_right:
    movq $1, move_dir(,%rcx,8)
    movq $KEY_HOLD, move_timer(,%rcx,8)
    jmp  .read_key

.jump:
    movq $1, jump_req(,%rcx,8)
    # tapping w while holding d stops d from repeating,
    # so a jump while running refills the run timer
    cmpq $0, move_timer(,%rcx,8)
    jle  .read_key
    movq $KEY_HOLD, move_timer(,%rcx,8)
    jmp  .read_key

.stop:
    movq $0, move_timer(,%rcx,8)
    jmp  .read_key

.grab:
    movq $1, grab_req(,%rcx,8)  # physics does the actual grab/throw
    jmp  .read_key

.enter:
    cmpq $SCENE_HOME, game_state
    je   .start_round
    cmpq $SCENE_END, game_state
    je   .start_round
    cmpq $SCENE_GAME, game_state
    je   .read_key              # does nothing mid-fight
    movq $SCENE_HOME, game_state # guide / credits -> back to menu
    jmp  .read_key

.start_round:
    call reset_round
    movq $SCENE_GAME, game_state
    jmp  .read_key

.guide:
    cmpq $SCENE_HOME, game_state # only from the menu
    jne  .read_key
    movq $SCENE_GUIDE, game_state
    jmp  .read_key

.credits:
    cmpq $SCENE_HOME, game_state
    jne  .read_key
    movq $SCENE_CREDITS, game_state
    jmp  .read_key

.quit:
    movq $1, quit_flag
    jmp  .read_key

.no_more_keys:
    # epilogue
    addq $8, %rsp
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret
