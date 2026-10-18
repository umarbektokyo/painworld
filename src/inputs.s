    #=============================================================================
    # painworld — src/inputs.s
    # Input handling. Reads ncurses getch() and translates keys into player
    # actions / game-state changes.
    #
    # Terminals only tell us "a key was typed", never "a key was released".
    # So a move key starts a countdown (move_timer = KEY_HOLD): the slugcat keeps
    # running while it is > 0, and the keyboard's auto-repeat keeps refilling it
    # while the key is held down.
    #
    # Key map:
    #   P1: a / d  run      w  jump     s  stop     q  grab / throw spear
    #   P2: arrows run      UP jump     DOWN stop   .  grab / throw spear
    #   Enter      menu: start | end screen: next round | guide/credits: back
    #   g / c      menu: guide / credits
    #   x / Esc    quit
    #=============================================================================

    .include "constants.inc"

    .text
    .globl poll_input

    #-----------------------------------------------------------------------------
    # void poll_input(void)
    #
    # Reads keys until getch() returns -1 (no more keys waiting), so several
    # key presses in one frame are all handled.
    # The player a key belongs to goes in %rcx (0 = P1, 1 = P2), so the same
    # code handles both players.
    #-----------------------------------------------------------------------------
poll_input:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx will hold the current key
    subq  $8, %rsp              # keep the stack 16-byte aligned for getch

.read_key:
    call getch                  # eax = key code, or -1 if no key waiting
    cmpl $-1, %eax
    je   .no_more_keys
    movl %eax, %ebx             # rbx = key code
    movq %rbx, last_key         # remember it for the HUD

    # quit
    cmpq $'x', %rbx
    je   .quit
    cmpq $KEY_ESC, %rbx
    je   .quit

    # next round
    cmpq $KEY_NEWLINE, %rbx
    je   .enter
    cmpq $KEY_RETURN, %rbx
    je   .enter
    cmpq $KEY_ENTER, %rbx
    je   .enter

    # menu
    cmpq $'g', %rbx
    je   .guide
    cmpq $'c', %rbx
    je   .credits

    # P1 (WASD)
    movq $0, %rcx               # player 0
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

    # P2 (arrow keys)
    movq $1, %rcx               # player 1
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

    jmp  .read_key              # some other key: ignore it

.move_left:
    movq $-1, move_dir(,%rcx,8)         # move_dir[p] = -1
    movq $KEY_HOLD, move_timer(,%rcx,8) # move_timer[p] = KEY_HOLD
    jmp  .read_key

.move_right:
    movq $1, move_dir(,%rcx,8)          # move_dir[p] = 1
    movq $KEY_HOLD, move_timer(,%rcx,8) # move_timer[p] = KEY_HOLD
    jmp  .read_key

.jump:
    movq $1, jump_req(,%rcx,8)          # jump_req[p] = 1
    # While you hold d and tap w, the terminal stops repeating d.
    # So a jump while running refills the run timer.
    cmpq $0, move_timer(,%rcx,8)
    jle  .read_key
    movq $KEY_HOLD, move_timer(,%rcx,8)
    jmp  .read_key

.stop:
    movq $0, move_timer(,%rcx,8)        # move_timer[p] = 0
    jmp  .read_key

.grab:
    movq $1, grab_req(,%rcx,8)          # grab_req[p] = 1 (physics handles it)
    jmp  .read_key

.enter:
    cmpq $SCENE_HOME, game_state        # menu: start a round
    je   .start_round
    cmpq $SCENE_END, game_state         # end screen: next round
    je   .start_round
    cmpq $SCENE_GUIDE, game_state       # guide / credits: back to the menu
    je   .to_home
    cmpq $SCENE_CREDITS, game_state
    je   .to_home
    jmp  .read_key                      # in the game: Enter does nothing

.start_round:
    call reset_round                    # see fights.s
    movq $SCENE_GAME, game_state
    jmp  .read_key

.to_home:
    movq $SCENE_HOME, game_state
    jmp  .read_key

.guide:
    cmpq $SCENE_HOME, game_state        # only from the menu
    jne  .read_key
    movq $SCENE_GUIDE, game_state
    jmp  .read_key

.credits:
    cmpq $SCENE_HOME, game_state        # only from the menu
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
