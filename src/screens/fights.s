    #=============================================================================
    # painworld — src/screens/fights.s
    # Game screen: physics update + drawing of the main playfield.
    #
    # For now each slugcat is two separate circles (head + body) that get the
    # same push from the keys. The springy spine that joins them comes next.
    #=============================================================================

    .include "constants.inc"

    .text
    .globl update_physics
    .globl draw_game

hud_text: .asciz " P1: a/d run, w jump, s stop | P2: arrows | x quit | key %3ld "

    #-----------------------------------------------------------------------------
    # void update_physics(void)
    #
    # Per-frame simulation step:
    #   for each chunk i (player p = i / 2):
    #       if move_timer[p] > 0: vx += (move_dir[p] * RUN_SPEED - vx) / 4
    #       else:                 vx  = vx * 7 / 8          (friction)
    #       if jump_req[p] && on_ground[p]: vy = -JUMP_SPEED
    #       vy = min(vy + GRAVITY, MAX_FALL)
    #       x += vx;  y += vy
    #   for each player p: move_timer[p]-- (if > 0), jump_req[p] = 0,
    #                      on_ground[p] = 0
    #   for each chunk i: collide_chunk(i)       (sets on_ground[p] again)
    #-----------------------------------------------------------------------------
update_physics:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = chunk index i  (or player index)
    pushq %r12                  # r12 = player index p of chunk i

    #-----------------------------------------------------------------------------
    # 1. Move every chunk
    #-----------------------------------------------------------------------------
    movq $0, %rbx
.move_loop:
    cmpq $NUM_CHUNKS, %rbx
    jge  .move_done

    movq %rbx, %r12
    shrq $1, %r12               # p = i / 2

    # running or friction?
    cmpq $0, move_timer(,%r12,8)
    jle  .friction

    # vx += (move_dir[p] * RUN_SPEED - vx) / 4    -> ease towards top speed
    movq move_dir(,%r12,8), %rax
    imulq $RUN_SPEED, %rax      # rax = target speed
    subq chunk_vx(,%rbx,8), %rax # rax = target - vx
    cqto                        # sign-extend rax into rdx (needed by idivq)
    movq $4, %rcx
    idivq %rcx                  # rax = (target - vx) / 4
    addq %rax, chunk_vx(,%rbx,8)
    jmp  .after_run

.friction:
    # vx = vx * 7 / 8    -> slow down a bit every frame
    movq chunk_vx(,%rbx,8), %rax
    imulq $7, %rax
    cqto
    movq $8, %rcx
    idivq %rcx                  # idivq rounds towards 0, so vx really reaches 0
    movq %rax, chunk_vx(,%rbx,8)

.after_run:
    # jump: only if requested AND standing on something
    cmpq $0, jump_req(,%r12,8)
    je   .no_jump
    cmpq $0, on_ground(,%r12,8)
    je   .no_jump
    movq $-JUMP_SPEED, chunk_vy(,%rbx,8) # negative = up
.no_jump:

    # gravity, capped at MAX_FALL
    addq $GRAVITY, chunk_vy(,%rbx,8)
    cmpq $MAX_FALL, chunk_vy(,%rbx,8)
    jle  .no_cap
    movq $MAX_FALL, chunk_vy(,%rbx,8)
.no_cap:

    # x += vx;  y += vy
    movq chunk_vx(,%rbx,8), %rax
    addq %rax, chunk_x(,%rbx,8)
    movq chunk_vy(,%rbx,8), %rax
    addq %rax, chunk_y(,%rbx,8)

    incq %rbx
    jmp  .move_loop
.move_done:

    #-----------------------------------------------------------------------------
    # 2. Per-player bookkeeping
    #-----------------------------------------------------------------------------
    movq $0, %rbx               # rbx = player index
.player_loop:
    cmpq $NUM_PLAYERS, %rbx
    jge  .players_done

    cmpq $0, move_timer(,%rbx,8)
    jle  .timer_done
    decq move_timer(,%rbx,8)    # one frame of running used up
.timer_done:
    movq $0, jump_req(,%rbx,8)  # jump request handled
    movq $0, on_ground(,%rbx,8) # collide_chunk sets it again if standing

    incq %rbx
    jmp  .player_loop
.players_done:

    #-----------------------------------------------------------------------------
    # 3. Collisions
    #-----------------------------------------------------------------------------
    movq $0, %rbx
.collide_loop:
    cmpq $NUM_CHUNKS, %rbx
    jge  .collide_done
    movq %rbx, %rdi
    call collide_chunk          # collide_chunk(i)
    incq %rbx
    jmp  .collide_loop
.collide_done:

    # epilogue
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void collide_chunk(long i /* %rdi */)
    #
    # Platforms are "land on top only": you can jump up through them.
    #   for each platform j:
    #       if vy >= 0                               (falling or resting)
    #       && x0[j] <= x <= x1[j]                   (above the platform)
    #       && y + r >= y0[j]                        (bottom is past the top now)
    #       && (y - vy) + r <= y0[j]:                (but was above it last frame)
    #           y = y0[j] - r;  vy = 0;  on_ground[i / 2] = 1
    #   then keep the chunk inside the left / right screen edges.
    #-----------------------------------------------------------------------------
collide_chunk:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq chunk_r(,%rdi,8), %r8  # r8 = radius
    movq $0, %rcx               # rcx = platform index j

.cc_loop:
    cmpq $NUM_PLATS, %rcx
    jge  .cc_walls

    cmpq $0, chunk_vy(,%rdi,8)  # moving up -> pass through
    jl   .cc_next

    movq chunk_x(,%rdi,8), %rax # is x between x0 and x1?
    cmpq plat_x0(,%rcx,8), %rax
    jl   .cc_next
    cmpq plat_x1(,%rcx,8), %rax
    jg   .cc_next

    movq chunk_y(,%rdi,8), %rax
    addq %r8, %rax              # rax = bottom of the chunk now
    cmpq plat_y0(,%rcx,8), %rax
    jl   .cc_next               # still above the top: not touching
    subq chunk_vy(,%rdi,8), %rax # rax = bottom of the chunk last frame
    cmpq plat_y0(,%rcx,8), %rax
    jg   .cc_next               # was already below the top: came from below

    # land on the platform
    movq plat_y0(,%rcx,8), %rax
    subq %r8, %rax
    movq %rax, chunk_y(,%rdi,8) # y = top - r
    movq $0, chunk_vy(,%rdi,8)  # vy = 0
    movq %rdi, %rax
    shrq $1, %rax               # rax = player index
    movq $1, on_ground(,%rax,8)

.cc_next:
    incq %rcx
    jmp  .cc_loop

.cc_walls:
    # left edge: if x < r: x = r, vx = 0
    cmpq %r8, chunk_x(,%rdi,8)
    jge  .cc_right
    movq %r8, chunk_x(,%rdi,8)
    movq $0, chunk_vx(,%rdi,8)
.cc_right:
    # right edge: if x > WORLD_W - r: x = WORLD_W - r, vx = 0
    movq $WORLD_W, %rax
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

    #-----------------------------------------------------------------------------
    # void draw_game(void)
    #
    # Layers (back to front): platforms + slugcats come from the brightness
    # sampler (draw_world), then the HUD text is written over the top row.
    #-----------------------------------------------------------------------------
draw_game:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    call draw_world             # see render.s

    # mvprintw(0, 0, hud_text, last_key)
    movq $0, %rdi               # row
    movq $0, %rsi               # column
    movq $hud_text, %rdx        # format string
    movq last_key, %rcx         # %ld in the format
    movq $0, %rax               # no float arguments (like printf)
    call mvprintw

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
