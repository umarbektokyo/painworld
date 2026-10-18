    .include "constants.inc"

    .text
    .globl update_physics
    .globl reset_round

# void reset_round(void)
# slugcats back to the start, new spears, rain back to a drizzle.
reset_round:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $0, %rcx               # chunk number i = 0 (4 chunks: P1 head/body, P2 head/body)

.rr_chunk_loop:
    cmpq $NUM_CHUNKS, %rcx      # done all 4 chunks?
    jge  .rr_chunks_done        #   yes -> go reset the players
    movq start_x(,%rcx,8), %rax # x = start x
    movq %rax, chunk_x(,%rcx,8)
    movq start_y(,%rcx,8), %rax # y = start y (high up, they fall in)
    movq %rax, chunk_y(,%rcx,8)
    movq $0, chunk_vx(,%rcx,8)  # not moving sideways
    movq $0, chunk_vy(,%rcx,8)  # not falling yet
    incq %rcx                   # next chunk
    jmp  .rr_chunk_loop

.rr_chunks_done:
    movq $0, %rcx               # player p = 0

.rr_player_loop:
    cmpq $NUM_PLAYERS, %rcx     # done both players?
    jge  .rr_players_done
    movq start_dir(,%rcx,8), %rax # face the start direction (P1 right, P2 left)
    movq %rax, move_dir(,%rcx,8)
    movq $0, move_timer(,%rcx,8) # not running
    movq $0, jump_req(,%rcx,8)  # forget keys pressed on the menu
    movq $0, grab_req(,%rcx,8)
    movq $0, on_ground(,%rcx,8) # in the air until we land
    movq $-1, held_spear(,%rcx,8) # empty hands
    incq %rcx                   # next player
    jmp  .rr_player_loop

.rr_players_done:
    call spawn_spears           # spears.s, new random spears
    call reset_rain             # rain.s, drizzle again, no water

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

# void update_physics(void)  - one frame of the whole simulation
#   1. move each chunk: run (head only) or friction, jump, gravity, x += vx, y += vy
#   2. per player: spine, grab/throw, count down timers
#   3. collisions with platforms + screen edges
#   4. spears,
#   5. rain + drowning
update_physics:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # chunk i (later player p)
    pushq %r12                  # player of chunk i = i / 2
    pushq %r13                  # part of chunk i = i % 2 (0 head, 1 body)
    subq  $8, %rsp              # 3 pushes = 24 bytes, +8 = 32, stack aligned

    # 1. move every chunk
    movq $0, %rbx               # i = 0

.move_loop:
    cmpq $NUM_CHUNKS, %rbx      # done all 4 chunks?
    jge  .move_done             #   yes -> step 2

    movq %rbx, %r12
    shrq $1, %r12               # p = i / 2   chunks 0,1 -> P1   2,3 -> P2
    movq %rbx, %r13
    andq $1, %r13               # part = i % 2   even = head, odd = body

    cmpq $1, %r13               # body never runs by itself, it gets dragged
    je   .friction              # by the spine instead
    cmpq $0, move_timer(,%r12,8) # no move key in the last 12 frames?
    jle  .friction              #   -> slow down instead of running

    # vx += (move_dir * RUN_SPEED - vx) / RUN_ACCEL, eases into top speed
    movq move_dir(,%r12,8), %rax # rax = 1 (right) or -1 (left)
    imulq $RUN_SPEED, %rax      # target speed = 32 or -32
    subq chunk_vx(,%rbx,8), %rax # how far we are from top speed
    cqto                        # sign-extend rax into rdx for idivq
    movq $RUN_ACCEL, %rcx       # take half of that gap each frame:
    idivq %rcx                  # speed goes 0, 16, 24, 28, 30...
    addq %rax, chunk_vx(,%rbx,8) # vx += half the gap
    jmp  .after_run

.friction:
    # vx = vx * 3 / 4
    movq chunk_vx(,%rbx,8), %rax # lose a quarter of the speed every frame:
    imulq $FRICTION_MUL, %rax   # 30, 22, 16, 12, 9 ... 0
    cqto                        # (x3 first, then /4, because 3/4 alone is 0)
    movq $FRICTION_DIV, %rcx
    idivq %rcx                  # idivq rounds towards 0, so vx does reach 0
    movq %rax, chunk_vx(,%rbx,8)

.after_run:
    cmpq $0, jump_req(,%r12,8)  # jump only if pressed and standing
    je   .no_jump
    cmpq $0, on_ground(,%r12,8) # in the air -> no double jumps
    je   .no_jump
    movq jump_kick(,%r13,8), %rax # head gets a bigger kick -> stretch
    negq %rax                   # up is negative (y grows downwards)
    movq %rax, chunk_vy(,%rbx,8) # vy = -64 head / -50 body, gravity does the rest

.no_jump:
    addq $GRAVITY, chunk_vy(,%rbx,8) # gravity: fall 5 faster every frame,
    cmpq $MAX_FALL, chunk_vy(,%rbx,8) # that's what makes the jump an arc
    jle  .no_cap
    movq $MAX_FALL, chunk_vy(,%rbx,8) # but never faster than 56

.no_cap:
    movq chunk_vx(,%rbx,8), %rax # x += vx, y += vy
    addq %rax, chunk_x(,%rbx,8) # (speed = how far we move this frame)
    movq chunk_vy(,%rbx,8), %rax
    addq %rax, chunk_y(,%rbx,8)

    incq %rbx                   # next chunk
    jmp  .move_loop

.move_done:
    # 2. per player
    movq $0, %rbx               # p = 0

.player_loop:
    cmpq $NUM_PLAYERS, %rbx     # done both players?
    jge  .players_done

    movq %rbx, %rdi             # spine(p: player)
    call spine                  # pull this player's head and body together

    cmpq $0, grab_req(,%rbx,8)  # spear key pressed?
    je   .no_grab
    movq %rbx, %rdi             # grab_or_throw(p: player), spears.s
    call grab_or_throw
    movq $0, grab_req(,%rbx,8)  # handled

.no_grab:
    cmpq $0, move_timer(,%rbx,8) # still running?
    jle  .timer_done
    decq move_timer(,%rbx,8)    # one frame of running used up

.timer_done:
    movq $0, jump_req(,%rbx,8)  # the jump already happened in step 1
    movq $0, on_ground(,%rbx,8) # collide_chunk sets it again if we're standing

    incq %rbx                   # next player
    jmp  .player_loop

.players_done:
    # 3. collisions
    movq $0, %rbx               # i = 0

.collide_loop:
    cmpq $NUM_CHUNKS, %rbx
    jge  .collide_done
    movq %rbx, %rdi             # collide_chunk(i: chunk)
    call collide_chunk          # land on platforms, stay on screen
    incq %rbx
    jmp  .collide_loop

.collide_done:
    call update_spears          # 4. spears.s
    call update_rain            # 5. rain.s
    call check_drowning         # head under water -> round over

    # epilogue
    addq $8, %rsp
    popq %r13
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

# void spine(long p /* %rdi */)
# spring between p's head and body, fixes 1/4 of the stretch every frame:
#   d  = isqrt(dx*dx + dy*dy)                    (dx, dy = head - body)
#   cx = dx * (d - REST_LEN) / (d * SPINE_DIV),  same for cy
#   head -= c, body += c       (both position and velocity, that's the spring)
spine:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # head index
    pushq %r12                  # body index
    pushq %r13                  # dx
    pushq %r14                  # dy

    movq %rdi, %rbx
    shlq $1, %rbx               # head = p * 2   (P1: 0, P2: 2)
    movq %rbx, %r12
    incq %r12                   # body = p * 2 + 1   (P1: 1, P2: 3)

    movq chunk_x(,%rbx,8), %r13
    subq chunk_x(,%r12,8), %r13 # dx = how far the head is from the body in x
    movq chunk_y(,%rbx,8), %r14
    subq chunk_y(,%r12,8), %r14 # dy = same in y

    movq %r13, %rdi
    imulq %r13, %rdi            # dx * dx
    movq %r14, %rax
    imulq %r14, %rax            # dy * dy
    addq %rax, %rdi             # isqrt(n: dx*dx + dy*dy)
    call isqrt                  # rax = d, the spine's length (pythagoras)

    cmpq $0, %rax               # on top of each other, no direction
    je   .spine_done

    movq %rax, %r8
    imulq $SPINE_DIV, %r8       # d * SPINE_DIV
    movq %rax, %r9
    subq $REST_LEN, %r9         # d - REST_LEN, how stretched it is
                                # (> 0 too long, < 0 squashed)

    movq %r13, %rax             # cx = dx * stretch / (d * 4)
    imulq %r9, %rax             # = a quarter of the stretch, in x
    cqto
    idivq %r8
    movq %rax, %r10

    movq %r14, %rax             # cy, same in y
    imulq %r9, %rax
    cqto
    idivq %r8
    movq %rax, %r11

    subq %r10, chunk_x(,%rbx,8) # head towards body
    subq %r10, chunk_vx(,%rbx,8) # (velocity too, not just position:
    subq %r11, chunk_y(,%rbx,8) #  that's what makes it bounce
    subq %r11, chunk_vy(,%rbx,8) #  like a spring instead of a stick)
    addq %r10, chunk_x(,%r12,8) # body towards head, same amount
    addq %r10, chunk_vx(,%r12,8)
    addq %r11, chunk_y(,%r12,8)
    addq %r11, chunk_vy(,%r12,8)

.spine_done:
    # epilogue
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

# long isqrt(long n /* %rdi */) -> %rax
# biggest r with r*r <= n. just counts up, fine since d is only ~60-100
isqrt:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $0, %rax               # r = 0
.isqrt_loop:
    movq %rax, %rcx
    incq %rcx                   # try r + 1
    imulq %rcx, %rcx            # (r + 1)^2
    cmpq %rdi, %rcx             # too big?
    jg   .isqrt_done            #   yes -> r is the answer
    incq %rax                   #   no -> r++
    jmp  .isqrt_loop

.isqrt_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

# void collide_chunk(long i /* %rdi */)
# land on a platform if we're falling and our bottom just crossed its top
# (was above it last frame). coming from below = go through. then screen edges.
collide_chunk:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq chunk_r(,%rdi,8), %r8  # radius
    movq $0, %rcx               # platform
.cc_loop:
    cmpq $NUM_PLATS, %rcx       # checked all 6 platforms?
    jge  .cc_walls

    cmpq $0, chunk_vy(,%rdi,8)  # going up -> pass through
    jl   .cc_next

    movq chunk_x(,%rdi,8), %rax # above the platform?
    cmpq plat_x0(,%rcx,8), %rax # left of it -> no
    jl   .cc_next
    cmpq plat_x1(,%rcx,8), %rax # right of it -> no
    jge  .cc_next               # x1 is already outside, like everywhere else

    movq chunk_y(,%rdi,8), %rax
    addq %r8, %rax              # bottom now
    cmpq plat_y0(,%rcx,8), %rax
    jl   .cc_next               # not there yet
    subq chunk_vy(,%rdi,8), %rax # bottom last frame
    cmpq plat_y0(,%rcx,8), %rax
    jg   .cc_next               # was already below, came from under it

    movq plat_y0(,%rcx,8), %rax # land: y = top - r, vy = 0
    subq %r8, %rax
    movq %rax, chunk_y(,%rdi,8) # sit exactly on top
    movq $0, chunk_vy(,%rdi,8)  # stop falling
    movq %rdi, %rax
    shrq $1, %rax               # player = chunk / 2
    movq $1, on_ground(,%rax,8) # standing -> can jump next frame

.cc_next:
    incq %rcx                   # next platform
    jmp  .cc_loop

.cc_walls:
    cmpq %r8, chunk_x(,%rdi,8)  # left: x >= r
    jge  .cc_right
    movq %r8, chunk_x(,%rdi,8)  # push back inside
    movq $0, chunk_vx(,%rdi,8)  # and stop
.cc_right:
    movq $WORLD_W, %rax         # right: x <= WORLD_W - r
    subq %r8, %rax
    cmpq %rax, chunk_x(,%rdi,8)
    jle  .cc_done
    movq %rax, chunk_x(,%rdi,8) # push back inside
    movq $0, chunk_vx(,%rdi,8)  # and stop

.cc_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
