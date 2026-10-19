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

    movq $0, %rcx                           # amount of drops is 0
.rr_drop_loop:
    cmpq $MAX_DROPS, %rcx                   # compare all possible drops to the current amount of drops, if greater or equal, then jump to .rr_drops_done
    jge  .rr_drops_done
    movq $0, drop_active(,%rcx,8)           # empty the free rain slot
    incq %rcx                               # go to the next slot
    jmp  .rr_drop_loop

.rr_drops_done:
    movq $0, %rcx                           # start at column 0

.rr_col_loop:
    cmpq $COLS, %rcx                        # if all available columns are done, jump to .rr_cols_done
    jge  .rr_cols_done
    movq $0, splash(,%rcx,8)                # there is no splash in this column
    incq %rcx                               # jump to the next column
    jmp  .rr_col_loop

.rr_cols_done:
    movq $0, %rcx                           # start at platform 0

.rr_plat_loop:
    cmpq $NUM_PLATS, %rcx                   # have all available platforms been checked? jump to .rr_plats_done
    jge  .rr_plats_done
    movq $0, plat_wet(,%rcx,8)              # platform is still dry
    incq %rcx                               # jump to the next platform
    jmp  .rr_plat_loop

.rr_plats_done:
    movq $0, water_total                    # total of water is 0
    movq $0, water_level                    # the water level is 0
    movq $RAIN_START, rain_level            # start again a light drizzle
    movq $0, rain_clock                     # start the clock for the rain

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
    pushq %rbx                              # drop
    subq  $8, %rsp                          # stack aligned for rand

    movq $0, %rbx                           # begin looking at drop slot 0

.sd_find:
    cmpq $MAX_DROPS, %rbx                   # if all drop slots have been handled, jump to .sd_done
    jge  .sd_done            
    cmpq $0, drop_active(,%rbx,8)           # is the current slot free? if so, then go use it to start a drop
    je   .sd_found       
    incq %rbx                               # if the slot is taken, jump to the next slot
    jmp  .sd_find

.sd_found:
    call rand                               # generate a random int
    movl %eax, %eax                         # put the random number in rdx
    movq $0, %rdx               
    movq $WORLD_W, %rcx         
    divq %rcx                   
    movq %rdx, drop_x(,%rbx,8)              # move the random value to the x coordinate of the drop
    movq $0, drop_y(,%rbx,8)                # move the drop to the top of the screen
    movq $1, drop_active(,%rbx,8)           # make the drop start falling

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
    pushq %rbx                              # drop
    pushq %r12                              # spawn attempt

    # 1. heavier rain
    incq rain_clock                         # increase the rain clock by one
    cmpq $RAIN_RAMP_FRAMES, rain_clock      # compare the rain clock with one second
    jl   .ur_spawn                          # if less than one second has happened, jump to .ur_spawn
    movq $0, rain_clock                     # start the rain clock again
    movq rain_level, %rax                   # move the rain level into rax
    movq $0, %rdx               
    movq $RAIN_GROWTH, %rcx
    divq %rcx                               # divide the rain growth by the rain level
    incq %rax                               # + 1 so the amount of rain still grows
    addq rain_level, %rax                   # one more rain level, so aroung 3% more rain
    cmpq $RAIN_MAX, %rax                    # are we at the max rain level? if not, jump to .ur_level_ok
    jle  .ur_level_ok
    movq $RAIN_MAX, %rax                    # cap the rain level at 1000

.ur_level_ok:
    movq %rax, rain_level                   # set the rain level increments at the current rain levels

    # 2. new drops
.ur_spawn:
    movq $0, %r12                           # initiate attempts at 0

.ur_spawn_loop:
    cmpq $RAIN_TRIES, %r12                  # have more or equal to 16 attempts happened? jump to .ur_move
    jge  .ur_move

    call rand                               # create a random number in rdx
    movl %eax, %eax            
    movq $0, %rdx
    movq $1000, %rcx                        # set the value of rcx at 1000
    divq %rcx                               
    cmpq rain_level, %rdx                   # is the random number greater or equal to the rain level? then jump to .ur_spawn_next
    jge  .ur_spawn_next         
    call spawn_drop                         # if it isn't, create a new drop

.ur_spawn_next:
    incq %r12                               # next attempt
    jmp  .ur_spawn_loop

    # 3. falling drops
.ur_move:
    movq $0, %rbx                           # initiate the drop at 0

.ur_move_loop:
    cmpq $MAX_DROPS, %rbx                   # if the drops are greater or equal than the max amount of drops, jump to .ur_splash
    jge  .ur_splash

    cmpq $0, drop_active(,%rbx,8)           # if the slot is empty, skip it
    je   .ur_move_next          

    addq $RAIN_SPEED, drop_y(,%rbx,8)       # add the speed of the rain to the y coordinate of the drop
    movq drop_x(,%rbx,8), %rdi              # rdi and rsi represent the x and y coordinates of the drop respectively
    movq drop_y(,%rbx,8), %rsi

    movq $FLOOR_TOP, %rax                   # subtract the top of the floor from the water level to get the water surface
    subq water_level, %rax     
    cmpq %rax, %rsi                         # if the drop falls under the water surface, jump to .ur_check_plats
    jl   .ur_check_plats        

    movq $0, drop_active(,%rbx,8)           # the drop landed so it is already done
    movq %rdi, %rcx
    shrq $4, %rcx                           # divide the column of the drop by 16
    cmpq $0, water_total                    # if the water total is greater than 0, then jump to .ur_add_water
    jg   .ur_add_water
    cmpq $0, splash(,%rcx,8)                # if a splash is still in this column, jump to .ur_add_water as well
    jg   .ur_add_water
    movq $SPLASH_FRAMES, splash(,%rcx,8)    # if the code got here, the floor is dry, so it just splashes
    jmp  .ur_move_next                      # splash is gone in 30 frames

.ur_add_water:
    addq $DROP_WATER, water_total           # the drop stays and the lake gets bigger
    movq $0, splash(,%rcx,8)                # the splash just becomes part of the lake now
    jmp  .ur_move_next                      # move to the next drop

.ur_check_plats:
    call find_platform                      # call the find_platform function from render.s
                                            # rax is either the platform or -1 if no platform
    cmpq $0, %rax
    jl   .ur_move_next                      # if there is no platform yet, the drop is still in the air

    addq $WET_PER_DROP, plat_wet(,%rax,8)   # the platform gets wetter
    cmpq $WET_MAX, plat_wet(,%rax,8)        # if the platform is still not as wet as can be, move to .ur_wet_ok
    jle  .ur_wet_ok
    movq $WET_MAX, plat_wet(,%rax,8)        # if it is greater than the max wetness of the platform, keep it at the cap

.ur_wet_ok:

    # drip off the nearer edge, so the water still ends up in the lake
    movq plat_x0(,%rax,8), %rcx
    addq plat_x1(,%rax,8), %rcx
    shrq $1, %rcx                           # get the middle of the drop (furthest minus closest edge of the platform halved)
    cmpq %rcx, %rdi                         # is the drop right of the middle? call .ur_drip_right
    jge  .ur_drip_right                     
    movq plat_x0(,%rax,8), %rcx
    decq %rcx                               # make the drop just left of the center
    movq %rcx, drop_x(,%rbx,8)              # keeps falling from there
    jmp  .ur_move_next

.ur_drip_right:
    movq plat_x1(,%rax,8), %rcx             # drop is just right of the platform
    movq %rcx, drop_x(,%rbx,8)              # drop keeps falling from there

.ur_move_next:
    incq %rbx                               # next drop
    jmp  .ur_move_loop

    # 4. drying
.ur_splash:
    movq $0, %rcx                           # initialize the column at 0

.ur_splash_loop:
    cmpq $COLS, %rcx                        # if all columns have been checked, jump to .ur_drain
    jge  .ur_drain
    cmpq $0, splash(,%rcx,8)                # is there a splash here? if not, jump to the next splash
    jle  .ur_splash_next
    decq splash(,%rcx,8)                    # bring the splash one frame closer to disappearing

.ur_splash_next:
    incq %rcx                               # next column
    jmp  .ur_splash_loop

.ur_drain:
    movq $0, %rcx                           # initialize the platform at 0

.ur_drain_loop:
    cmpq $NUM_PLATS, %rcx                   # have all platforms been checked? If so, jump to .ur_level
    jge  .ur_level
    cmpq $0, plat_wet(,%rcx,8)              # is the platform wet? If not, jump to the next platform
    jle  .ur_drain_next
    decq plat_wet(,%rcx,8)                  # platform dries slowly, only stays wet if the rain is heavy enough

.ur_drain_next:
    incq %rcx                               # next platform
    jmp  .ur_drain_loop

    # 5. flat lake
.ur_level:
    movq water_total, %rax                  # divides the water total amongst all available columns
    movq $0, %rdx
    movq $COLS, %rcx
    divq %rcx                   
    movq %rax, water_level                  # evens the heigth, all lakes have the same height

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

    cmpq $SCENE_END, game_state             # check if the scene has ended already, if so, then jump to .cd_done
    je   .cd_done                           

    movq $FLOOR_TOP, %r8
    subq water_level, %r8                   # get the water surface (water level - top of the floor)

    movq $0, %rcx                           # start checking the players starting from player 0

.cd_loop:
    cmpq $NUM_PLAYERS, %rcx                 # have both players been checked? if so, jump to .cd_decide
    jge  .cd_decide
    movq $0, drowned(,%rcx,8)               # assume the player hasn't drowned
    movq %rcx, %rax
    shlq $1, %rax                           # focus on the head chunk
    cmpq %r8, chunk_y(,%rax,8)              # is the head bellow the water surface? if not, jump to .cd_next
    jle  .cd_next               
    movq $1, drowned(,%rcx,8)               # if it is, raise the amount of drowned players by one

.cd_next:
    incq %rcx                               # next player
    jmp  .cd_loop

.cd_decide:
    movq drowned, %rax
    addq drowned+8, %rax                    # check how many players have drowned
    cmpq $0, %rax                           # if no players have drowned, jump to .cd_done
    je   .cd_done               
    movq $SCENE_END, game_state             # but if someone did, then this stage is over
    cmpq $2, %rax                           # and if both have drowned, then it's a draw (jump to .cd_draw)
    je   .cd_draw

    movq $1, winner                         # there is one winner
    cmpq $1, drowned                        # if there was also one drowned, then change the score (.cd_score)
    je   .cd_score
    movq $0, winner                         # otherwise, this player didn't win

.cd_score:
    movq winner, %rax
    incq kills(,%rax,8)                     # winner gets a point
    jmp  .cd_done

.cd_draw:
    movq $-1, winner                        # there is -1 winners, so it's a draw and nobody gets a point

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
    pushq %rbx                              # drop / column, survives mvaddch
    subq  $8, %rsp                          # stack aligned for mvaddch

    movq $0, %rbx                           # initialize amount of drops at 0

.dr_drop_loop:
    cmpq $MAX_DROPS, %rbx                   # have all possible drops fallen? then jump to .dr_splashes
    jge  .dr_splashes
    cmpq $0, drop_active(,%rbx,8)           # are you on an empty drop slot? then there's nothing to draw
    je   .dr_drop_next                      

    # mvaddch(row: y / 32, col: x / 16, ch: ' in blue)
    movq drop_y(,%rbx,8), %rdi
    shrq $5, %rdi                           # divide the y coordinate of the drop by 32 (a cell is only 32 bits tall)
    movq drop_x(,%rbx,8), %rsi
    shrq $4, %rsi                           # divide the x coordinate of the drop by 16 (a cell is only 16 bits wide)
    movq $WATER_PAIR, %rdx                  # make the drops blue
    shlq $8, %rdx                           # COLOR_PAIR(WATER_PAIR)
    orq  $39, %rdx                          # bitwise or between 39 and the value in rdc
    call mvaddch                            # add the drop

.dr_drop_next:
    incq %rbx                               # next drop
    jmp  .dr_drop_loop

.dr_splashes:
    movq $0, %rbx                           # initialize columns at 0

.dr_splash_loop:
    cmpq $COLS, %rbx                        # if all columns have been checked, jump to .dr_done
    jge  .dr_done
    cmpq $0, splash(,%rbx,8)                # is there a splash in this column? if not, then jump to .dr_splash_next
    jle  .dr_splash_next       

    # mvaddch(row: SPLASH_ROW, col: column, ch: . in blue)
    movq $SPLASH_ROW, %rdi                  # have the row and column stored in rdi and rsi respectively
    movq %rbx, %rsi             
    movq $WATER_PAIR, %rdx                  # move the order to make a pair of drops
    shlq $8, %rdx                           # make the drop blue
    orq  $'.', %rdx                         # print the '.' character (raindrop)
    call mvaddch

.dr_splash_next:
    incq %rbx                               # next column
    jmp  .dr_splash_loop

.dr_done:
    # epilogue
    addq $8, %rsp
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret
