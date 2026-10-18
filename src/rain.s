    #=============================================================================
    # painworld — src/rain.s
    # Rain system: spawn, update, draw. Rain drops fall at RAIN_SPEED.
    # Rain-on-ground disappears after 1 sec. Rain-on-rain does NOT disappear
    # (accumulation / drought mechanic).
    #=============================================================================

    .section .text
    .globl spawn_rain
    .globl update_rain
    .globl draw_rain

    #-----------------------------------------------------------------------------
    # void spawn_rain(void)
    #
    # Each frame, with probability RAIN_SPAWN_CH/100, activate one inactive
    # rain drop at a random X at the top of the screen.
    #
    # Formula:
    #   if random(0, 99) < RAIN_SPAWN_CH:
    #       find i where rain_active[i] == 0
    #       rain_x[i]  = random(0, SCREEN_W)
    #       rain_y[i]  = 0
    #       rain_active[i] = 1
    #-----------------------------------------------------------------------------
spawn_rain:
    push %rbp
    mov  %rsp, %rbp

    # TODO: implement random() call or simple LCG
    # TODO: loop over MAX_RAIN drops, find inactive, activate

    pop %rbp
    ret

    #-----------------------------------------------------------------------------
    # void update_rain(void)
    #
    # For each active drop:
    #   rain_y[i] += RAIN_SPEED
    #   if rain_y[i] >= SCREEN_H: rain_active[i] = 0   # hits ground -> disappears
    #   # rain-on-rain does NOT disappear (drought mechanic)
    #-----------------------------------------------------------------------------
update_rain:
    push %rbp
    mov  %rsp, %rbp

    # TODO: loop over MAX_RAIN, update each active drop
    # Formula: rain_y[i] = rain_y[i] + RAIN_SPEED
    #          if rain_y[i] >= SCREEN_H << 16: rain_active[i] = 0

    pop %rbp
    ret

    #-----------------------------------------------------------------------------
    # void draw_rain(void)
    #
    # For each active drop, draw a rain character at (rain_y[i], rain_x[i]).
    # Character: '.' (light rain)
    #
    # C call: mvaddch(row: %rdi, col: %rsi, ch: %rdx)
    #-----------------------------------------------------------------------------
draw_rain:
    push %rbp
    mov  %rsp, %rbp

    # TODO: loop over MAX_RAIN, if active call mvaddch(rain_y, rain_x, '.')
    # mvaddch(row: %rdi, col: %rsi, ch: %rdx) -> %rax

    pop %rbp
    ret
