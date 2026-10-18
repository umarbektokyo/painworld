# main.s - ncurses setup + the main loop
#
# every frame (~30 fps): read keys, clear, draw the current scene, refresh, sleep

    .include "constants.inc"

    .text
    .globl main

utf8_locale:    .asciz "C.UTF-8"
too_small_text: .asciz "Make the terminal bigger: painworld needs %d x %d (x quits)"

main:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # setlocale(LC_ALL, "C.UTF-8") so the title's unicode blocks work,
    # has to be before initscr
    movq $LC_ALL, %rdi
    movq $utf8_locale, %rsi
    call setlocale

    call initscr                # ncurses takes over the terminal
    call noecho                 # don't print typed keys
    call cbreak                 # keys come in right away, no Enter needed

    movq stdscr, %rdi           # keypad(stdscr, 1): arrows become KEY_LEFT etc
    movq $1, %rsi
    call keypad

    movq $0, %rdi               # curs_set(0): hide the cursor
    call curs_set

    movq $0, %rdi               # timeout(0): getch returns -1 right away if
    call timeout                # nothing was pressed

    movq $25, %rdi              # Esc normally takes 1 second to arrive
    call set_escdelay

    call start_color

    # colour pairs: init_pair(pair, foreground, background = 0 black)
    movq $1, %rdi               # 1 = P1 green
    movq $P1_COLOR, %rsi
    movq $0, %rdx
    call init_pair

    movq $2, %rdi               # 2 = P2 orange
    movq $P2_COLOR, %rsi
    movq $0, %rdx
    call init_pair

    movq $WATER_PAIR, %rdi      # 3 = rain + water, blue
    movq $4, %rsi
    movq $0, %rdx
    call init_pair

    movq $SKY_PAIR, %rdi        # 4 = clouds, grey-blue
    movq $SKY_COLOR, %rsi
    movq $0, %rdx
    call init_pair

    movq $0, %rdi               # srand(time(0)), so spears differ every run
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
    movq stdscr, %rdi
    call getmaxy                # eax = height
    cmpl $ROWS, %eax
    jl   .too_small
    movq stdscr, %rdi
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
    movq $0, %rdi               # mvprintw(0, 0, too_small_text, COLS, ROWS)
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

    movq $FRAME_US, %rdi        # usleep(33000)
    call usleep
    jmp  .game_loop

.done:
    call endwin                 # give the terminal back

    # epilogue
    movq $0, %rax
    movq %rbp, %rsp
    popq %rbp
    ret
