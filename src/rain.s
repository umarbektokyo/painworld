    #=============================================================================
    # painworld — src/rain.s
    # Rain and the flood.
    #
    # Raindrops fall from random spots at the top. When a drop reaches the floor
    # in column c:
    #   - dry floor (no water yet, no splash in c): it leaves a splash that
    #     disappears after SPLASH_FRAMES (about 1 second)
    #   - it lands on a splash or on water ("rain on rain"): it STAYS and adds
    #     DROP_WATER to water_total
    # The floor is one connected basin, so the water is always flat:
    #     water_level = water_total / COLS
    # The rain gets heavier over time, so splashes get hit more and more often,
    # puddles appear, spread out and rise: the flood. Whoever's head goes under
    # drowns.
    #=============================================================================

    .include "constants.inc"

    .text
    .globl reset_rain
    .globl update_rain
    .globl check_drowning
    .globl draw_rain

    #-----------------------------------------------------------------------------
    # void reset_rain(void)
    #
    # No drops, no water, no splashes; light rain again.
    #-----------------------------------------------------------------------------
reset_rain:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $0, %rcx               # rcx = drop index
.rr_drop_loop:
    cmpq $MAX_DROPS, %rcx
    jge  .rr_drops_done
    movq $0, drop_active(,%rcx,8)
    incq %rcx
    jmp  .rr_drop_loop
.rr_drops_done:

    movq $0, %rcx               # rcx = column
.rr_col_loop:
    cmpq $COLS, %rcx
    jge  .rr_cols_done
    movq $0, splash(,%rcx,8)
    incq %rcx
    jmp  .rr_col_loop
.rr_cols_done:

    movq $0, water_total
    movq $0, water_level
    movq $RAIN_START, rain_level
    movq $0, rain_clock

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void spawn_drop(void)
    #
    # Find a free drop slot and start it at a random x at the top of the screen.
    # If all MAX_DROPS are falling already, do nothing.
    #-----------------------------------------------------------------------------
spawn_drop:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = drop index
    subq  $8, %rsp              # keep the stack 16-byte aligned for rand

    movq $0, %rbx
.sd_find:
    cmpq $MAX_DROPS, %rbx
    jge  .sd_done               # no free slot
    cmpq $0, drop_active(,%rbx,8)
    je   .sd_found
    incq %rbx
    jmp  .sd_find

.sd_found:
    call rand                   # x = rand() % WORLD_W
    movl %eax, %eax             # clear the top half of rax (rand returns int)
    movq $0, %rdx
    movq $WORLD_W, %rcx
    divq %rcx                   # rdx = rax % WORLD_W
    movq %rdx, drop_x(,%rbx,8)
    movq $0, drop_y(,%rbx,8)    # top of the screen
    movq $1, drop_active(,%rbx,8)

.sd_done:
    # epilogue
    addq $8, %rsp
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void update_rain(void)
    #
    #   1. every RAIN_RAMP_FRAMES frames:
    #          rain_level += rain_level / RAIN_GROWTH + 1   (up to RAIN_MAX)
    #      Growing by a fraction of itself means the more it rains, the faster
    #      it gets worse: a drizzle at first, pouring after ~2 minutes.
    #   2. RAIN_TRIES times: if rand() % 1000 < rain_level: spawn_drop()
    #   3. for each falling drop:
    #          y += RAIN_SPEED;  c = x / 16
    #          if y >= FLOOR_TOP - water_level:        (reached floor / water)
    #              drop stops
    #              if water_total > 0 or splash[c] > 0: water_total += DROP_WATER
    #              else:                                splash[c] = SPLASH_FRAMES
    #          else if inside a platform (not the floor):
    #              move it to the platform's nearer edge (it drips off there)
    #   4. every splash[c] counts down by 1
    #   5. water_level = water_total / COLS
    #-----------------------------------------------------------------------------
update_rain:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = drop index
    pushq %r12                  # r12 = spawn attempt counter

    #-----------------------------------------------------------------------------
    # 1. heavier and heavier rain
    #-----------------------------------------------------------------------------
    incq rain_clock
    cmpq $RAIN_RAMP_FRAMES, rain_clock
    jl   .ur_spawn
    movq $0, rain_clock
    movq rain_level, %rax
    movq $0, %rdx
    movq $RAIN_GROWTH, %rcx
    divq %rcx                   # rax = rain_level / RAIN_GROWTH
    incq %rax                   # ... + 1
    addq rain_level, %rax       # rax = new rain_level
    cmpq $RAIN_MAX, %rax
    jle  .ur_level_ok
    movq $RAIN_MAX, %rax        # cap it
.ur_level_ok:
    movq %rax, rain_level

    #-----------------------------------------------------------------------------
    # 2. new drops
    #-----------------------------------------------------------------------------
.ur_spawn:
    movq $0, %r12
.ur_spawn_loop:
    cmpq $RAIN_TRIES, %r12
    jge  .ur_move

    call rand                   # rdx = rand() % 1000
    movl %eax, %eax
    movq $0, %rdx
    movq $1000, %rcx
    divq %rcx
    cmpq rain_level, %rdx       # rain_level out of 1000 chance
    jge  .ur_spawn_next
    call spawn_drop

.ur_spawn_next:
    incq %r12
    jmp  .ur_spawn_loop

    #-----------------------------------------------------------------------------
    # 3. falling drops
    #-----------------------------------------------------------------------------
.ur_move:
    movq $0, %rbx
.ur_move_loop:
    cmpq $MAX_DROPS, %rbx
    jge  .ur_splash

    cmpq $0, drop_active(,%rbx,8)
    je   .ur_move_next

    addq $RAIN_SPEED, drop_y(,%rbx,8)
    movq drop_x(,%rbx,8), %rdi  # rdi, rsi = the drop's point
    movq drop_y(,%rbx,8), %rsi

    movq %rdi, %rcx
    shrq $4, %rcx               # rcx = column = x / 16
    movq $FLOOR_TOP, %rax
    subq water_level, %rax      # rax = water surface
    cmpq %rax, %rsi
    jl   .ur_check_plats        # still above it

    # reached the floor / the water
    movq $0, drop_active(,%rbx,8)
    cmpq $0, water_total
    jg   .ur_add_water
    cmpq $0, splash(,%rcx,8)
    jg   .ur_add_water
    movq $SPLASH_FRAMES, splash(,%rcx,8) # dry floor: splash, gone in a second
    jmp  .ur_move_next

.ur_add_water:
    addq $DROP_WATER, water_total        # rain on rain: it stays
    movq $0, splash(,%rcx,8)
    jmp  .ur_move_next

.ur_check_plats:
    movq $1, %rcx               # start at 1: platform 0 is the floor (above)
.ur_plat_loop:
    cmpq $NUM_PLATS, %rcx
    jge  .ur_move_next

    cmpq plat_x0(,%rcx,8), %rdi
    jl   .ur_plat_next
    cmpq plat_x1(,%rcx,8), %rdi
    jge  .ur_plat_next
    cmpq plat_y0(,%rcx,8), %rsi
    jl   .ur_plat_next
    cmpq plat_y1(,%rcx,8), %rsi
    jge  .ur_plat_next

    # hit a platform: the water runs off to the nearer edge and drips from
    # there, so it still ends up in the lake
    movq plat_x0(,%rcx,8), %rax
    addq plat_x1(,%rcx,8), %rax
    shrq $1, %rax               # rax = middle of the platform
    cmpq %rax, %rdi
    jge  .ur_drip_right
    movq plat_x0(,%rcx,8), %rax
    decq %rax                   # just left of the platform
    movq %rax, drop_x(,%rbx,8)
    jmp  .ur_move_next
.ur_drip_right:
    movq plat_x1(,%rcx,8), %rax # just right of it (x1 is already outside)
    movq %rax, drop_x(,%rbx,8)
    jmp  .ur_move_next

.ur_plat_next:
    incq %rcx
    jmp  .ur_plat_loop

.ur_move_next:
    incq %rbx
    jmp  .ur_move_loop

    #-----------------------------------------------------------------------------
    # 4. splashes dry up
    #-----------------------------------------------------------------------------
.ur_splash:
    movq $0, %rcx               # rcx = column
.ur_splash_loop:
    cmpq $COLS, %rcx
    jge  .ur_level
    cmpq $0, splash(,%rcx,8)
    jle  .ur_splash_next
    decq splash(,%rcx,8)
.ur_splash_next:
    incq %rcx
    jmp  .ur_splash_loop

    #-----------------------------------------------------------------------------
    # 5. flat lake: water_level = water_total / COLS
    #-----------------------------------------------------------------------------
.ur_level:
    movq water_total, %rax
    movq $0, %rdx
    movq $COLS, %rcx
    divq %rcx                   # rax = water_total / COLS
    movq %rax, water_level

.ur_done:
    # epilogue
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void check_drowning(void)
    #
    #   if game_state == SCENE_END: return          (a spear already won)
    #   for each player p:
    #       drowned[p] = head.y > FLOOR_TOP - water_level  (head under water)
    #   both drowned -> winner = -1 (draw)
    #   one drowned  -> the other one wins:  kills[winner]++
    #   any drowned  -> game_state = SCENE_END
    #-----------------------------------------------------------------------------
check_drowning:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    cmpq $SCENE_END, game_state
    je   .cd_done

    movq $0, %rcx               # rcx = player
.cd_loop:
    cmpq $NUM_PLAYERS, %rcx
    jge  .cd_decide

    movq $0, drowned(,%rcx,8)
    movq %rcx, %r8
    shlq $1, %r8                # r8 = head chunk = p * 2
    movq $FLOOR_TOP, %rax
    subq water_level, %rax      # rax = water surface
    cmpq %rax, chunk_y(,%r8,8)
    jle  .cd_next               # head is above the water
    movq $1, drowned(,%rcx,8)

.cd_next:
    incq %rcx
    jmp  .cd_loop

.cd_decide:
    movq drowned, %rax
    addq drowned+8, %rax        # rax = how many drowned
    cmpq $0, %rax
    je   .cd_done               # nobody: keep playing
    movq $SCENE_END, game_state
    cmpq $2, %rax
    je   .cd_draw

    movq $1, winner             # one drowned: if it was P1, P2 wins...
    cmpq $1, drowned
    je   .cd_score
    movq $0, winner             # ...otherwise P1 wins
.cd_score:
    movq winner, %rax
    incq kills(,%rax,8)
    jmp  .cd_done

.cd_draw:
    movq $-1, winner            # both drowned: nobody scores

.cd_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void draw_rain(void)
    #
    # Falling drops: a blue apostrophe at (y / 32, x / 16).
    # Splashes on dry floor: a blue '.' on the row just above the floor.
    # (The water itself is drawn by the brightness sampler, see render.s.)
    #-----------------------------------------------------------------------------
draw_rain:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = drop index / column
    subq  $8, %rsp              # keep the stack 16-byte aligned for mvaddch

    movq $0, %rbx
.dr_drop_loop:
    cmpq $MAX_DROPS, %rbx
    jge  .dr_splashes
    cmpq $0, drop_active(,%rbx,8)
    je   .dr_drop_next

    movq drop_y(,%rbx,8), %rdi
    shrq $5, %rdi               # row = y / 32
    movq drop_x(,%rbx,8), %rsi
    shrq $4, %rsi               # col = x / 16
    movq $WATER_PAIR, %rdx
    shlq $8, %rdx               # COLOR_PAIR(WATER_PAIR)
    orq  $39, %rdx              # 39 = ' (apostrophe)
    call mvaddch

.dr_drop_next:
    incq %rbx
    jmp  .dr_drop_loop

.dr_splashes:
    movq $0, %rbx               # rbx = column
.dr_splash_loop:
    cmpq $COLS, %rbx
    jge  .dr_done
    cmpq $0, splash(,%rbx,8)
    jle  .dr_splash_next

    movq $SPLASH_ROW, %rdi
    movq %rbx, %rsi
    movq $WATER_PAIR, %rdx
    shlq $8, %rdx
    orq  $'.', %rdx
    call mvaddch

.dr_splash_next:
    incq %rbx
    jmp  .dr_splash_loop

.dr_done:
    # epilogue
    addq $8, %rsp
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret
