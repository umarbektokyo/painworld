    #=============================================================================
    # painworld — src/screens/home.s
    # Home screen: ASCII title + [Start] [Guide] [Credits] menu.
    #=============================================================================

    .section .text
    .globl draw_home

    #-----------------------------------------------------------------------------
    # void draw_home(void)
    #
    # Renders the home screen using ncurses mvaddch / addstr.
    # Waits for input; on 'Enter' transitions to SCENE_GAME.
    #-----------------------------------------------------------------------------
draw_home:
    push %rbp
    mov  %rsp, %rbp

    # erase() -> %rax       # clear buffer
    # erase(void): %rax = OK
    call erase

    # TODO: draw ASCII art title at center
    # TODO: draw menu options
    # TODO: refresh()

    pop %rbp
    ret
