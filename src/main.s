    #=============================================================================
    # painworld — src/main.s
    # Entry point. Initializes ncurses, runs the main game loop, dispatches
    # between scenes (home / game / end / guide / credits).
    #
    # Game loop (~30 frames per second):
    #   while !quit_flag:
    #       poll_input()
    #       erase()
    #       switch game_state:
    #         SCENE_GAME: update_physics(); draw_game()
    #         SCENE_END:  draw_end()
    #         otherwise:  draw_home()          (other scenes come later)
    #       refresh()
    #       usleep(33000)
    #=============================================================================

    .include "constants.inc"

    .text
    .globl main

main:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    #-----------------------------------------------------------------------------
    # ncurses setup
    #-----------------------------------------------------------------------------
    call initscr                # take over the terminal

    call noecho                 # don't print the keys the user types

    call cbreak                 # give us keys immediately, no Enter needed

    movq stdscr, %rdi           # keypad(stdscr, 1): turn arrow keys into
    movq $1, %rsi               # single codes like KEY_LEFT
    call keypad

    movq $0, %rdi               # curs_set(0): hide the cursor
    call curs_set

    movq $0, %rdi               # timeout(0): getch() never waits, it returns
    call timeout                # -1 straight away if no key was pressed

    movq $25, %rdi              # set_escdelay(25): Esc arrives after 25 ms
    call set_escdelay           # instead of the default 1 second

    call start_color            # enable colours

    movq $1, %rdi               # init_pair(1, YELLOW, BLACK): P1's colour
    movq $3, %rsi
    movq $0, %rdx
    call init_pair

    movq $2, %rdi               # init_pair(2, RED, BLACK): P2's colour
    movq $1, %rsi
    movq $0, %rdx
    call init_pair

    #-----------------------------------------------------------------------------
    # first round
    #-----------------------------------------------------------------------------
    movq $0, %rdi               # srand(time(0)): different spears every run
    call time
    movq %rax, %rdi
    call srand

    call reset_round            # place slugcats + spears (see fights.s)

    #-----------------------------------------------------------------------------
    # Main game loop
    #-----------------------------------------------------------------------------
.game_loop:
    call poll_input             # read every key pressed since last frame

    cmpq $1, quit_flag          # x or Esc pressed -> stop
    je   .done

    call erase                  # clear the screen buffer

    # Scene dispatch based on game_state
    cmpq $SCENE_GAME, game_state
    je   .scene_game
    cmpq $SCENE_END, game_state
    je   .scene_end
    # SCENE_HOME / GUIDE / CREDITS: only the home stub exists for now
    call draw_home
    jmp  .frame_end

.scene_end:
    call draw_end               # frozen fight + winner (see screens/end.s)
    jmp  .frame_end

.scene_game:
    call update_physics         # move everything one frame forward
    call draw_game              # draw the world + HUD

.frame_end:
    call refresh                # show what we drew

    movq $FRAME_US, %rdi        # usleep(33000): wait for the next frame
    call usleep

    jmp  .game_loop

    #-----------------------------------------------------------------------------
    # Cleanup
    #-----------------------------------------------------------------------------
.done:
    call endwin                 # give the terminal back (important!)

    # epilogue, return 0
    movq $0, %rax
    movq %rbp, %rsp
    popq %rbp
    ret
