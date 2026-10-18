    #=============================================================================
    # painworld — src/main.s
    # Entry point. Initializes ncurses, runs the main game loop, dispatches
    # between scenes (home / game / end / guide / credits).
    #
    # Game loop (~30 frames per second):
    #   while !quit_flag:
    #       poll_input()
    #       erase()
    #       if the terminal is smaller than COLS x ROWS: show a message, skip
    #       switch game_state:
    #         SCENE_GAME: update_physics(); draw_game()
    #         SCENE_END:  draw_end()
    #         SCENE_GUIDE: draw_guide();  SCENE_CREDITS: draw_credits()
    #         SCENE_HOME: draw_home()
    #       refresh()
    #       usleep(33000)
    #=============================================================================

    .include "constants.inc"

    .text
    .globl main

utf8_locale: .asciz "C.UTF-8"
too_small_text: .asciz "Make the terminal bigger: painworld needs %d x %d (x quits)"

main:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # setlocale(LC_ALL, "C.UTF-8"): let ncursesw print UTF-8 (the title).
    # Must happen before initscr().
    movq $LC_ALL, %rdi
    movq $utf8_locale, %rsi
    call setlocale

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

    # Player colours: the nice ones need a 256-colour terminal.
    # COLORS is a global int from ncurses (set by start_color).
    cmpl $256, COLORS
    jl   .basic_colours

    movq $1, %rdi               # init_pair(1, P1_COLOR, BLACK): P1 green
    movq $P1_COLOR, %rsi
    movq $0, %rdx
    call init_pair

    movq $2, %rdi               # init_pair(2, P2_COLOR, BLACK): P2 orange
    movq $P2_COLOR, %rsi
    movq $0, %rdx
    call init_pair
    jmp  .colours_done

.basic_colours:
    movq $1, %rdi               # init_pair(1, GREEN, BLACK)
    movq $P1_COLOR_8, %rsi
    movq $0, %rdx
    call init_pair

    movq $2, %rdi               # init_pair(2, RED, BLACK)
    movq $P2_COLOR_8, %rsi
    movq $0, %rdx
    call init_pair

.colours_done:

    movq $3, %rdi               # init_pair(3, BLUE, BLACK): rain + water
    movq $4, %rsi
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

    # Terminal too small? Ask for a bigger one and pause everything.
    movq stdscr, %rdi
    call getmaxy                # eax = terminal height
    cmpl $ROWS, %eax
    jl   .too_small
    movq stdscr, %rdi
    call getmaxx                # eax = terminal width
    cmpl $COLS, %eax
    jl   .too_small

    # Scene dispatch based on game_state
    cmpq $SCENE_GAME, game_state
    je   .scene_game
    cmpq $SCENE_END, game_state
    je   .scene_end
    cmpq $SCENE_GUIDE, game_state
    je   .scene_guide
    cmpq $SCENE_CREDITS, game_state
    je   .scene_credits
    call draw_home              # SCENE_HOME (see screens/home.s)
    jmp  .frame_end

.too_small:
    # mvprintw(0, 0, too_small_text, COLS, ROWS)
    movq $0, %rdi
    movq $0, %rsi
    movq $too_small_text, %rdx
    movq $COLS, %rcx
    movq $ROWS, %r8
    movq $0, %rax
    call mvprintw
    jmp  .frame_end

.scene_guide:
    call draw_guide             # see screens/guide.s
    jmp  .frame_end

.scene_credits:
    call draw_credits           # see screens/credits.s
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
