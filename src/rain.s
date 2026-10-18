# the rain, the flood, the drowning
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

    movq $0, %rcx               # drop i = 0 (rcx is fine, nothing is called)

.rr_drop_loop:
    cmpq $MAX_DROPS, %rcx       # done all 1024 drop slots?
    jge  .rr_drops_done
    movq $0, drop_active(,%rcx,8) # slot is free, nothing falling
    incq %rcx                   # next slot
    jmp  .rr_drop_loop

.rr_drops_done:
    movq $0, %rcx               # column = 0

.rr_col_loop:
    cmpq $COLS, %rcx            # done all 120 columns?
    jge  .rr_cols_done
    movq $0, splash(,%rcx,8)    # no splash in this column
    incq %rcx                   # next column
    jmp  .rr_col_loop

.rr_cols_done:
    movq $0, %rcx               # platform = 0

.rr_plat_loop:
    cmpq $NUM_PLATS, %rcx       # done all 6 platforms?
    jge  .rr_plats_done
    movq $0, plat_wet(,%rcx,8)  # platform top is dry
    incq %rcx                   # next platform
    jmp  .rr_plat_loop

.rr_plats_done:
    movq $0, water_total        # no water at all
    movq $0, water_level        # lake height = 0
    movq $RAIN_START, rain_level # light drizzle again (8 out of 1000)
    movq $0, rain_clock         # start counting to the next "heavier" step

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

    movq $0, %rbx               # look from slot 0

.sd_find:
    cmpq $MAX_DROPS, %rbx       # looked at every slot?
    jge  .sd_done               # all busy, skip
    cmpq $0, drop_active(,%rbx,8) # is this slot free?
    je   .sd_found              #   yes -> use it
    incq %rbx                   #   no -> try the next one
    jmp  .sd_find

.sd_found:
    call rand                   # x = rand() % WORLD_W
    movl %eax, %eax             # rand gives an int, clear the top half of rax
    movq $0, %rdx               # divq divides rdx:rax, so rdx must be 0
    movq $WORLD_W, %rcx         # divide by the world width (1920)
    divq %rcx                   # remainder in rdx = random x on the screen
    movq %rdx, drop_x(,%rbx,8)  # x = that
    movq $0, drop_y(,%rbx,8)    # y = 0, the very top
    movq $1, drop_active(,%rbx,8) # now it's falling

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
    incq rain_clock             # one more frame since the last step up
    cmpq $RAIN_RAMP_FRAMES, rain_clock # 30 frames = 1 second yet?
    jl   .ur_spawn              #   not yet -> skip
    movq $0, rain_clock         # start counting again
    movq rain_level, %rax       # rax = rain_level / 32 + 1
    movq $0, %rdx               # (rdx = 0 before divq, like in spawn_drop)
    movq $RAIN_GROWTH, %rcx
    divq %rcx                   # rain_level / 32
    incq %rax                   # + 1, so it still grows when it's small
    addq rain_level, %rax       # new level: about 3% more every second
    cmpq $RAIN_MAX, %rax        # more than 1000?
    jle  .ur_level_ok
    movq $RAIN_MAX, %rax        #   cap it at 1000 (16 drops per frame)

.ur_level_ok:
    movq %rax, rain_level

    # 2. new drops
.ur_spawn:
    movq $0, %r12               # attempt = 0

.ur_spawn_loop:
    cmpq $RAIN_TRIES, %r12      # done 16 attempts?
    jge  .ur_move

    call rand                   # rand() % 1000 < rain_level ?
    movl %eax, %eax             # clear the top half of rax
    movq $0, %rdx
    movq $1000, %rcx
    divq %rcx                   # rdx = random number 0..999
    cmpq rain_level, %rdx       # smaller than rain_level?
    jge  .ur_spawn_next         #   no -> no drop this time
    call spawn_drop             #   yes -> a new drop at the top

.ur_spawn_next:
    incq %r12                   # next attempt
    jmp  .ur_spawn_loop

    # 3. falling drops
.ur_move:
    movq $0, %rbx               # drop i = 0

.ur_move_loop:
    cmpq $MAX_DROPS, %rbx       # done all slots?
    jge  .ur_splash

    cmpq $0, drop_active(,%rbx,8) # empty slot?
    je   .ur_move_next          #   skip it

    addq $RAIN_SPEED, drop_y(,%rbx,8) # fall 24 down (rain falls at a constant speed)
    movq drop_x(,%rbx,8), %rdi  # rdi, rsi = where the drop is now
    movq drop_y(,%rbx,8), %rsi

    movq $FLOOR_TOP, %rax       # reached the lake / floor?
    subq water_level, %rax      # rax = water surface (the floor, minus the water)
    cmpq %rax, %rsi
    jl   .ur_check_plats        # still above it -> maybe it hit a platform

    movq $0, drop_active(,%rbx,8) # it landed, this drop is done
    movq %rdi, %rcx
    shrq $4, %rcx               # column = x / 16
    cmpq $0, water_total        # already water, or a splash here -> it stays
    jg   .ur_add_water
    cmpq $0, splash(,%rcx,8)    # a splash still in this column? (rain on rain)
    jg   .ur_add_water
    movq $SPLASH_FRAMES, splash(,%rcx,8) # dry floor, just a splash
    jmp  .ur_move_next          # (gone again in 30 frames)

.ur_add_water:
    addq $DROP_WATER, water_total # this drop stays, the lake gets 8 bigger
    movq $0, splash(,%rcx,8)    # the splash is part of the water now
    jmp  .ur_move_next

.ur_check_plats:
    call find_platform          # find_platform(x: drop x, y: drop y), render.s
                                # rax = platform or -1
    cmpq $0, %rax
    jl   .ur_move_next          # still in the air

    addq $WET_PER_DROP, plat_wet(,%rax,8) # platform gets wetter
    cmpq $WET_MAX, plat_wet(,%rax,8) # more than 128?
    jle  .ur_wet_ok
    movq $WET_MAX, plat_wet(,%rax,8) #   cap it (render.s draws a 16 tall film max)

.ur_wet_ok:

    # drip off the nearer edge, so the water still ends up in the lake
    movq plat_x0(,%rax,8), %rcx
    addq plat_x1(,%rax,8), %rcx
    shrq $1, %rcx               # middle of the platform = (x0 + x1) / 2
    cmpq %rcx, %rdi             # drop right of the middle?
    jge  .ur_drip_right         #   -> drips off the right edge
    movq plat_x0(,%rax,8), %rcx
    decq %rcx                   # just left of it
    movq %rcx, drop_x(,%rbx,8)  # it keeps falling from there next frame
    jmp  .ur_move_next

.ur_drip_right:
    movq plat_x1(,%rax,8), %rcx # just right of it (x1 is already outside)
    movq %rcx, drop_x(,%rbx,8)

.ur_move_next:
    incq %rbx                   # next drop
    jmp  .ur_move_loop

    # 4. drying
.ur_splash:
    movq $0, %rcx               # column = 0

.ur_splash_loop:
    cmpq $COLS, %rcx            # done all columns?
    jge  .ur_drain
    cmpq $0, splash(,%rcx,8)    # splash here?
    jle  .ur_splash_next
    decq splash(,%rcx,8)        # one frame closer to disappearing

.ur_splash_next:
    incq %rcx                   # next column
    jmp  .ur_splash_loop

.ur_drain:
    movq $0, %rcx               # platform = 0

.ur_drain_loop:
    cmpq $NUM_PLATS, %rcx       # done all platforms?
    jge  .ur_level
    cmpq $0, plat_wet(,%rcx,8)  # wet?
    jle  .ur_drain_next
    decq plat_wet(,%rcx,8)      # dries a little every frame, so it only
                                # stays wet if the rain is heavy enough
.ur_drain_next:
    incq %rcx                   # next platform
    jmp  .ur_drain_loop

    # 5. flat lake
.ur_level:
    movq water_total, %rax      # spread all the water over the whole floor:
    movq $0, %rdx
    movq $COLS, %rcx
    divq %rcx                   # water_level = water_total / 120
    movq %rax, water_level      # (same height everywhere, a flat lake)

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

    cmpq $SCENE_END, game_state # a spear already won this frame?
    je   .cd_done               #   then don't overwrite the winner

    movq $FLOOR_TOP, %r8
    subq water_level, %r8       # surface

    movq $0, %rcx               # player

.cd_loop:
    cmpq $NUM_PLAYERS, %rcx     # done both players?
    jge  .cd_decide
    movq $0, drowned(,%rcx,8)   # assume fine
    movq %rcx, %rax
    shlq $1, %rax               # head chunk
    cmpq %r8, chunk_y(,%rax,8)  # head below the surface? (y grows downwards)
    jle  .cd_next               # head above water
    movq $1, drowned(,%rcx,8)   # under water -> drowned

.cd_next:
    incq %rcx                   # next player
    jmp  .cd_loop

.cd_decide:
    movq drowned, %rax
    addq drowned+8, %rax        # how many drowned
    cmpq $0, %rax               # nobody?
    je   .cd_done               #   keep playing
    movq $SCENE_END, game_state # somebody did -> round over
    cmpq $2, %rax               # both at once?
    je   .cd_draw

    movq $1, winner             # P1 drowned -> P2 wins
    cmpq $1, drowned
    je   .cd_score
    movq $0, winner             # otherwise P1 wins

.cd_score:
    movq winner, %rax
    incq kills(,%rax,8)         # winner gets a point
    jmp  .cd_done

.cd_draw:
    movq $-1, winner            # -1 = draw, nobody gets a point

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
    pushq %rbx                  # drop / column, survives mvaddch
    subq  $8, %rsp              # stack aligned for mvaddch

    movq $0, %rbx               # drop i = 0

.dr_drop_loop:
    cmpq $MAX_DROPS, %rbx       # done all slots?
    jge  .dr_splashes
    cmpq $0, drop_active(,%rbx,8) # empty slot?
    je   .dr_drop_next          #   nothing to draw

    # mvaddch(row: y / 32, col: x / 16, ch: ' in blue)
    movq drop_y(,%rbx,8), %rdi
    shrq $5, %rdi               # row = y / 32 (a cell is 32 tall)
    movq drop_x(,%rbx,8), %rsi
    shrq $4, %rsi               # col = x / 16 (a cell is 16 wide)
    movq $WATER_PAIR, %rdx
    shlq $8, %rdx               # COLOR_PAIR(WATER_PAIR)
    orq  $39, %rdx              # 39 = '
    call mvaddch

.dr_drop_next:
    incq %rbx                   # next drop
    jmp  .dr_drop_loop

.dr_splashes:
    movq $0, %rbx               # column

.dr_splash_loop:
    cmpq $COLS, %rbx            # done all columns?
    jge  .dr_done
    cmpq $0, splash(,%rbx,8)    # splash in this column?
    jle  .dr_splash_next        #   no -> nothing to draw

    # mvaddch(row: SPLASH_ROW, col: column, ch: . in blue)
    movq $SPLASH_ROW, %rdi      # the row just above the floor
    movq %rbx, %rsi             # this column
    movq $WATER_PAIR, %rdx
    shlq $8, %rdx               # blue
    orq  $'.', %rdx             # + the '.' character
    call mvaddch

.dr_splash_next:
    incq %rbx                   # next column
    jmp  .dr_splash_loop

.dr_done:
    # epilogue
    addq $8, %rsp
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret
