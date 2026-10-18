# physics.s - moving the slugcats + round reset
#
# a slugcat = 2 circles (head, body) + a springy spine between them.
# keys only push the head, the spine drags the body along. that's all the
# animation there is: lean when running, stretch on jumps, squash on landing.

    .include "constants.inc"

    .text
    .globl update_physics
    .globl reset_round

# void reset_round(void)
# slugcats back to the start, new spears, rain back to a drizzle.
# kills aren't reset, so the score carries over.
reset_round:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $0, %rcx               # chunk
.rr_chunk_loop:
    cmpq $NUM_CHUNKS, %rcx
    jge  .rr_chunks_done
    movq start_x(,%rcx,8), %rax
    movq %rax, chunk_x(,%rcx,8)
    movq start_y(,%rcx,8), %rax
    movq %rax, chunk_y(,%rcx,8)
    movq $0, chunk_vx(,%rcx,8)
    movq $0, chunk_vy(,%rcx,8)
    incq %rcx
    jmp  .rr_chunk_loop
.rr_chunks_done:

    movq $0, %rcx               # player
.rr_player_loop:
    cmpq $NUM_PLAYERS, %rcx
    jge  .rr_players_done
    movq start_dir(,%rcx,8), %rax
    movq %rax, move_dir(,%rcx,8)
    movq $0, move_timer(,%rcx,8)
    movq $0, jump_req(,%rcx,8)
    movq $0, grab_req(,%rcx,8)
    movq $0, on_ground(,%rcx,8)
    movq $-1, held_spear(,%rcx,8)
    incq %rcx
    jmp  .rr_player_loop
.rr_players_done:

    call spawn_spears           # spears.s
    call reset_rain             # rain.s

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

# void update_physics(void)  - one frame of the whole simulation
#   1. move each chunk: run (head only) or friction, jump, gravity, x += vx, y += vy
#   2. per player: spine, grab/throw, count down timers
#   3. collisions with platforms + screen edges
#   4. spears, 5. rain + drowning
update_physics:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # chunk i (later player p)
    pushq %r12                  # player of chunk i = i / 2
    pushq %r13                  # part of chunk i = i % 2 (0 head, 1 body)
    subq  $8, %rsp              # stack aligned

    # 1. move every chunk
    movq $0, %rbx
.move_loop:
    cmpq $NUM_CHUNKS, %rbx
    jge  .move_done

    movq %rbx, %r12
    shrq $1, %r12               # p = i / 2
    movq %rbx, %r13
    andq $1, %r13               # part = lowest bit of i

    cmpq $1, %r13               # body never runs by itself
    je   .friction
    cmpq $0, move_timer(,%r12,8)
    jle  .friction

    # vx += (move_dir * RUN_SPEED - vx) / RUN_ACCEL, eases into top speed
    movq move_dir(,%r12,8), %rax
    imulq $RUN_SPEED, %rax      # target speed
    subq chunk_vx(,%rbx,8), %rax
    cqto                        # sign-extend rax into rdx for idivq
    movq $RUN_ACCEL, %rcx
    idivq %rcx
    addq %rax, chunk_vx(,%rbx,8)
    jmp  .after_run

.friction:
    # vx = vx * 3 / 4
    movq chunk_vx(,%rbx,8), %rax
    imulq $FRICTION_MUL, %rax
    cqto
    movq $FRICTION_DIV, %rcx
    idivq %rcx                  # idivq rounds towards 0, so vx does reach 0
    movq %rax, chunk_vx(,%rbx,8)

.after_run:
    cmpq $0, jump_req(,%r12,8)  # jump only if pressed and standing
    je   .no_jump
    cmpq $0, on_ground(,%r12,8)
    je   .no_jump
    movq jump_kick(,%r13,8), %rax # head gets a bigger kick -> stretch
    negq %rax                   # up is negative
    movq %rax, chunk_vy(,%rbx,8)
.no_jump:

    addq $GRAVITY, chunk_vy(,%rbx,8)
    cmpq $MAX_FALL, chunk_vy(,%rbx,8)
    jle  .no_cap
    movq $MAX_FALL, chunk_vy(,%rbx,8)
.no_cap:

    movq chunk_vx(,%rbx,8), %rax # x += vx, y += vy
    addq %rax, chunk_x(,%rbx,8)
    movq chunk_vy(,%rbx,8), %rax
    addq %rax, chunk_y(,%rbx,8)

    incq %rbx
    jmp  .move_loop
.move_done:

    # 2. per player
    movq $0, %rbx
.player_loop:
    cmpq $NUM_PLAYERS, %rbx
    jge  .players_done

    movq %rbx, %rdi
    call spine

    cmpq $0, grab_req(,%rbx,8)
    je   .no_grab
    movq %rbx, %rdi
    call grab_or_throw          # spears.s
    movq $0, grab_req(,%rbx,8)
.no_grab:

    cmpq $0, move_timer(,%rbx,8)
    jle  .timer_done
    decq move_timer(,%rbx,8)
.timer_done:
    movq $0, jump_req(,%rbx,8)
    movq $0, on_ground(,%rbx,8) # collide_chunk sets it again if we're standing

    incq %rbx
    jmp  .player_loop
.players_done:

    # 3. collisions
    movq $0, %rbx
.collide_loop:
    cmpq $NUM_CHUNKS, %rbx
    jge  .collide_done
    movq %rbx, %rdi
    call collide_chunk
    incq %rbx
    jmp  .collide_loop
.collide_done:

    call update_spears          # 4. spears.s
    call update_rain            # 5. rain.s
    call check_drowning

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
    shlq $1, %rbx               # head = p * 2
    movq %rbx, %r12
    incq %r12                   # body = p * 2 + 1

    movq chunk_x(,%rbx,8), %r13
    subq chunk_x(,%r12,8), %r13 # dx
    movq chunk_y(,%rbx,8), %r14
    subq chunk_y(,%r12,8), %r14 # dy

    movq %r13, %rdi
    imulq %r13, %rdi
    movq %r14, %rax
    imulq %r14, %rax
    addq %rax, %rdi             # dx*dx + dy*dy
    call isqrt                  # rax = d

    cmpq $0, %rax               # on top of each other, no direction
    je   .spine_done

    movq %rax, %r8
    imulq $SPINE_DIV, %r8       # d * SPINE_DIV
    movq %rax, %r9
    subq $REST_LEN, %r9         # d - REST_LEN, how stretched it is

    movq %r13, %rax             # cx
    imulq %r9, %rax
    cqto
    idivq %r8
    movq %rax, %r10

    movq %r14, %rax             # cy
    imulq %r9, %rax
    cqto
    idivq %r8
    movq %rax, %r11

    subq %r10, chunk_x(,%rbx,8) # head towards body
    subq %r10, chunk_vx(,%rbx,8)
    subq %r11, chunk_y(,%rbx,8)
    subq %r11, chunk_vy(,%rbx,8)
    addq %r10, chunk_x(,%r12,8) # body towards head
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

    movq $0, %rax
.isqrt_loop:
    movq %rax, %rcx
    incq %rcx
    imulq %rcx, %rcx            # (r + 1)^2
    cmpq %rdi, %rcx
    jg   .isqrt_done
    incq %rax
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
    cmpq $NUM_PLATS, %rcx
    jge  .cc_walls

    cmpq $0, chunk_vy(,%rdi,8)  # going up -> pass through
    jl   .cc_next

    movq chunk_x(,%rdi,8), %rax # above the platform?
    cmpq plat_x0(,%rcx,8), %rax
    jl   .cc_next
    cmpq plat_x1(,%rcx,8), %rax
    jg   .cc_next

    movq chunk_y(,%rdi,8), %rax
    addq %r8, %rax              # bottom now
    cmpq plat_y0(,%rcx,8), %rax
    jl   .cc_next               # not there yet
    subq chunk_vy(,%rdi,8), %rax # bottom last frame
    cmpq plat_y0(,%rcx,8), %rax
    jg   .cc_next               # was already below, came from under it

    movq plat_y0(,%rcx,8), %rax # land: y = top - r, vy = 0
    subq %r8, %rax
    movq %rax, chunk_y(,%rdi,8)
    movq $0, chunk_vy(,%rdi,8)
    movq %rdi, %rax
    shrq $1, %rax
    movq $1, on_ground(,%rax,8)

.cc_next:
    incq %rcx
    jmp  .cc_loop

.cc_walls:
    cmpq %r8, chunk_x(,%rdi,8)  # left: x >= r
    jge  .cc_right
    movq %r8, chunk_x(,%rdi,8)
    movq $0, chunk_vx(,%rdi,8)
.cc_right:
    movq $WORLD_W, %rax         # right: x <= WORLD_W - r
    subq %r8, %rax
    cmpq %rax, chunk_x(,%rdi,8)
    jle  .cc_done
    movq %rax, chunk_x(,%rdi,8)
    movq $0, chunk_vx(,%rdi,8)

.cc_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
