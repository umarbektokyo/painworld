# main.s - ncurses setup + the main loop
# every frame (~30 fps): read keys, clear, draw the current scene, refresh, sleep

    .include "constants.inc"

    .text
    .globl main

utf8_locale:    .asciz "C.UTF-8"
too_small_text: .asciz "pls make the terminal bigger, painworld consumes %d x %d (x quits)"

main:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # setlocale(category: LC_ALL, locale: "C.UTF-8") so the title's unicode blocks work
    movq $LC_ALL, %rdi
    movq $utf8_locale, %rsi
    call setlocale

    call initscr                # ncurses takes over the terminal
    call noecho                 # don't print typed keys
    call cbreak                 # keys come-in right away, no Enter needed

    # keypad(window: stdscr, on: 1), arrows become KEY_LEFT etc
    movq stdscr, %rdi
    movq $1, %rsi
    call keypad

    movq $0, %rdi               # curs_set(visibility: 0), hide the cursor
    call curs_set

    movq $0, %rdi               # timeout(ms: 0), getch returns -1 right away
    call timeout                # if nothing was pressed

    movq $1, %rdi               # set_escdelay(ms: 1), Esc normally takes
    call set_escdelay           # 1 second to arrive

    call start_color

    # colour pairs: init_pair(pair: n, fg: colour, bg: 0 = black)
    movq $1, %rdi               # init_pair(pair: 1, fg: P1_COLOR, bg: 0), P1 green
    movq $P1_COLOR, %rsi
    movq $0, %rdx
    call init_pair

    movq $2, %rdi               # init_pair(pair: 2, fg: P2_COLOR, bg: 0), P2 orange
    movq $P2_COLOR, %rsi
    movq $0, %rdx
    call init_pair

    movq $WATER_PAIR, %rdi      # init_pair(pair: 3, fg: 4 blue, bg: 0), water
    movq $4, %rsi
    movq $0, %rdx
    call init_pair

    movq $SKY_PAIR, %rdi        # init_pair(pair: 4, fg: SKY_COLOR, bg: 0), clouds
    movq $SKY_COLOR, %rsi
    movq $0, %rdx
    call init_pair

    movq $0, %rdi               # srand(seed: time(NULL)), new spears every run
    call time
    movq %rax, %rdi
    call srand

    call reset_round            # physics.s

.game_loop:
    call poll_input             # inputs.s
    incq frame_count

    cmpq $1, quit_flag
    je   .done

    call erase

    # terminal too small -> just show a message
    movq stdscr, %rdi           # getmaxy(window: stdscr)
    call getmaxy                # eax = height
    cmpl $ROWS, %eax
    jl   .too_small
    movq stdscr, %rdi           # getmaxx(window: stdscr)
    call getmaxx                # eax = width
    cmpl $COLS, %eax
    jl   .too_small

    # pick the scene
    cmpq $SCENE_GAME, game_state
    je   .scene_game
    cmpq $SCENE_END, game_state
    je   .scene_end
    cmpq $SCENE_GUIDE, game_state
    je   .scene_guide
    cmpq $SCENE_CREDITS, game_state
    je   .scene_credits
    call draw_home
    jmp  .frame_end

.too_small:
    # mvprintw(row: 0, col: 0, format: too_small_text, %d: COLS, %d: ROWS)
    movq $0, %rdi
    movq $0, %rsi
    movq $too_small_text, %rdx
    movq $COLS, %rcx
    movq $ROWS, %r8
    movq $0, %rax
    call mvprintw
    jmp  .frame_end

.scene_guide:
    call draw_guide
    jmp  .frame_end

.scene_credits:
    call draw_credits
    jmp  .frame_end

.scene_end:
    call draw_end               # frozen fight + who won
    jmp  .frame_end

.scene_game:
    call update_physics
    call draw_game

.frame_end:
    call refresh                # actually show it

    movq $FRAME_US, %rdi        # usleep(microseconds: 33000)
    call usleep
    jmp  .game_loop

.done:
    call endwin                 # give the terminal back

    # epilogue
    movq $0, %rax
    movq %rbp, %rsp
    popq %rbp
    ret
