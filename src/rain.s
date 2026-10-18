# rain.s - rain, the flood, drowning
#
# drops fall from random x. when one hits the floor in column c:
#   - dry floor (no water yet, no splash in c): leaves a splash, gone in ~1s
#   - lands on a splash or on water (rain on rain): it stays, water_total += 8
# drops hitting a platform make its top wetter and drip off the nearer edge.
# the rain gets heavier over time, so the lake starts and keeps rising.
# the floor is one big basin so the lake is flat: water_level = water_total / COLS

    .include "constants.inc"

    .text
    .globl reset_rain
    .globl update_rain
    .globl check_drowning
    .globl draw_rain

# void reset_rain(void) - no drops, no water, back to a drizzle
reset_rain:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $0, %rcx
.rr_drop_loop:
    cmpq $MAX_DROPS, %rcx
    jge  .rr_drops_done
    movq $0, drop_active(,%rcx,8)
    incq %rcx
    jmp  .rr_drop_loop
.rr_drops_done:

    movq $0, %rcx
.rr_col_loop:
    cmpq $COLS, %rcx
    jge  .rr_cols_done
    movq $0, splash(,%rcx,8)
    incq %rcx
    jmp  .rr_col_loop
.rr_cols_done:

    movq $0, %rcx
.rr_plat_loop:
    cmpq $NUM_PLATS, %rcx
    jge  .rr_plats_done
    movq $0, plat_wet(,%rcx,8)
    incq %rcx
    jmp  .rr_plat_loop
.rr_plats_done:

    movq $0, water_total
    movq $0, water_level
    movq $RAIN_START, rain_level
    movq $0, rain_clock

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

# void spawn_drop(void) - start a drop in a free slot at a random x
spawn_drop:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # drop
    subq  $8, %rsp              # stack aligned for rand

    movq $0, %rbx
.sd_find:
    cmpq $MAX_DROPS, %rbx
    jge  .sd_done               # all busy, skip
    cmpq $0, drop_active(,%rbx,8)
    je   .sd_found
    incq %rbx
    jmp  .sd_find

.sd_found:
    call rand                   # x = rand() % WORLD_W
    movl %eax, %eax
    movq $0, %rdx
    movq $WORLD_W, %rcx
    divq %rcx
    movq %rdx, drop_x(,%rbx,8)
    movq $0, drop_y(,%rbx,8)
    movq $1, drop_active(,%rbx,8)

.sd_done:
    # epilogue
    addq $8, %rsp
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

# void update_rain(void)
#   1. every second: rain_level += rain_level / 32 + 1 (grows faster the more it rains)
#   2. RAIN_TRIES times: spawn a drop with chance rain_level / 1000
#   3. move drops, land them on the floor/water or on platforms
#   4. splashes + wet platforms dry up a bit
#   5. water_level = water_total / COLS
update_rain:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # drop
    pushq %r12                  # spawn attempt

    # 1. heavier rain
    incq rain_clock
    cmpq $RAIN_RAMP_FRAMES, rain_clock
    jl   .ur_spawn
    movq $0, rain_clock
    movq rain_level, %rax
    movq $0, %rdx
    movq $RAIN_GROWTH, %rcx
    divq %rcx
    incq %rax
    addq rain_level, %rax       # new level
    cmpq $RAIN_MAX, %rax
    jle  .ur_level_ok
    movq $RAIN_MAX, %rax
.ur_level_ok:
    movq %rax, rain_level

    # 2. new drops
.ur_spawn:
    movq $0, %r12
.ur_spawn_loop:
    cmpq $RAIN_TRIES, %r12
    jge  .ur_move

    call rand                   # rand() % 1000 < rain_level ?
    movl %eax, %eax
    movq $0, %rdx
    movq $1000, %rcx
    divq %rcx
    cmpq rain_level, %rdx
    jge  .ur_spawn_next
    call spawn_drop

.ur_spawn_next:
    incq %r12
    jmp  .ur_spawn_loop

    # 3. falling drops
.ur_move:
    movq $0, %rbx
.ur_move_loop:
    cmpq $MAX_DROPS, %rbx
    jge  .ur_splash

    cmpq $0, drop_active(,%rbx,8)
    je   .ur_move_next

    addq $RAIN_SPEED, drop_y(,%rbx,8)
    movq drop_x(,%rbx,8), %rdi
    movq drop_y(,%rbx,8), %rsi

    movq $FLOOR_TOP, %rax       # reached the lake / floor?
    subq water_level, %rax
    cmpq %rax, %rsi
    jl   .ur_check_plats

    movq $0, drop_active(,%rbx,8)
    movq %rdi, %rcx
    shrq $4, %rcx               # column = x / 16
    cmpq $0, water_total        # already water, or a splash here -> it stays
    jg   .ur_add_water
    cmpq $0, splash(,%rcx,8)
    jg   .ur_add_water
    movq $SPLASH_FRAMES, splash(,%rcx,8) # dry floor, just a splash
    jmp  .ur_move_next

.ur_add_water:
    addq $DROP_WATER, water_total
    movq $0, splash(,%rcx,8)
    jmp  .ur_move_next

.ur_check_plats:
    call find_platform          # find_platform(x: drop x, y: drop y), render.s
                                # rax = platform or -1
    cmpq $0, %rax
    jl   .ur_move_next          # still in the air

    addq $WET_PER_DROP, plat_wet(,%rax,8) # platform gets wetter
    cmpq $WET_MAX, plat_wet(,%rax,8)
    jle  .ur_wet_ok
    movq $WET_MAX, plat_wet(,%rax,8)
.ur_wet_ok:

    # drip off the nearer edge, so the water still ends up in the lake
    movq plat_x0(,%rax,8), %rcx
    addq plat_x1(,%rax,8), %rcx
    shrq $1, %rcx               # middle of the platform
    cmpq %rcx, %rdi
    jge  .ur_drip_right
    movq plat_x0(,%rax,8), %rcx
    decq %rcx                   # just left of it
    movq %rcx, drop_x(,%rbx,8)
    jmp  .ur_move_next
.ur_drip_right:
    movq plat_x1(,%rax,8), %rcx # just right of it (x1 is already outside)
    movq %rcx, drop_x(,%rbx,8)

.ur_move_next:
    incq %rbx
    jmp  .ur_move_loop

    # 4. drying
.ur_splash:
    movq $0, %rcx
.ur_splash_loop:
    cmpq $COLS, %rcx
    jge  .ur_drain
    cmpq $0, splash(,%rcx,8)
    jle  .ur_splash_next
    decq splash(,%rcx,8)
.ur_splash_next:
    incq %rcx
    jmp  .ur_splash_loop

.ur_drain:
    movq $0, %rcx
.ur_drain_loop:
    cmpq $NUM_PLATS, %rcx
    jge  .ur_level
    cmpq $0, plat_wet(,%rcx,8)
    jle  .ur_drain_next
    decq plat_wet(,%rcx,8)
.ur_drain_next:
    incq %rcx
    jmp  .ur_drain_loop

    # 5. flat lake
.ur_level:
    movq water_total, %rax
    movq $0, %rdx
    movq $COLS, %rcx
    divq %rcx
    movq %rax, water_level

    # epilogue
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

# void check_drowning(void)
# head below the water surface = drowned. one drowns -> the other wins,
# both at once -> draw (winner = -1). skipped if a spear already ended the round.
check_drowning:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    cmpq $SCENE_END, game_state
    je   .cd_done

    movq $FLOOR_TOP, %r8
    subq water_level, %r8       # surface

    movq $0, %rcx               # player
.cd_loop:
    cmpq $NUM_PLAYERS, %rcx
    jge  .cd_decide
    movq $0, drowned(,%rcx,8)
    movq %rcx, %rax
    shlq $1, %rax               # head chunk
    cmpq %r8, chunk_y(,%rax,8)
    jle  .cd_next               # head above water
    movq $1, drowned(,%rcx,8)
.cd_next:
    incq %rcx
    jmp  .cd_loop

.cd_decide:
    movq drowned, %rax
    addq drowned+8, %rax        # how many drowned
    cmpq $0, %rax
    je   .cd_done
    movq $SCENE_END, game_state
    cmpq $2, %rax
    je   .cd_draw

    movq $1, winner             # P1 drowned -> P2 wins
    cmpq $1, drowned
    je   .cd_score
    movq $0, winner             # otherwise P1 wins
.cd_score:
    movq winner, %rax
    incq kills(,%rax,8)
    jmp  .cd_done

.cd_draw:
    movq $-1, winner

.cd_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

# void draw_rain(void)
# drops = blue ' at (y / 32, x / 16), splashes = blue . just above the floor.
# (the water itself is drawn by the sampler in render.s)
draw_rain:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx
    subq  $8, %rsp              # stack aligned for mvaddch

    movq $0, %rbx
.dr_drop_loop:
    cmpq $MAX_DROPS, %rbx
    jge  .dr_splashes
    cmpq $0, drop_active(,%rbx,8)
    je   .dr_drop_next

    # mvaddch(row: y / 32, col: x / 16, ch: ' in blue)
    movq drop_y(,%rbx,8), %rdi
    shrq $5, %rdi
    movq drop_x(,%rbx,8), %rsi
    shrq $4, %rsi
    movq $WATER_PAIR, %rdx
    shlq $8, %rdx               # COLOR_PAIR(WATER_PAIR)
    orq  $39, %rdx              # 39 = '
    call mvaddch

.dr_drop_next:
    incq %rbx
    jmp  .dr_drop_loop

.dr_splashes:
    movq $0, %rbx               # column
.dr_splash_loop:
    cmpq $COLS, %rbx
    jge  .dr_done
    cmpq $0, splash(,%rbx,8)
    jle  .dr_splash_next

    # mvaddch(row: SPLASH_ROW, col: column, ch: . in blue)
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
