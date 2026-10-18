    #=============================================================================
    # painworld — src/screens/fights.s
    # Game screen: physics update + drawing of the main playfield.
    #
    # Each slugcat is two circles (head + body) joined by a springy spine.
    # Only the head is driven by the keys; the spine drags the body along.
    # That is the whole procedural animation: lean when running, stretch when
    # jumping, squash when landing all come out of the same few rules.
    #=============================================================================

    .include "constants.inc"

    .text
    .globl update_physics
    .globl draw_game
    .globl reset_round

hud_text: .asciz " P1: wasd + q spear | P2: arrows + . spear | x quit | kills %ld - %ld "

    #-----------------------------------------------------------------------------
    # void reset_round(void)
    #
    # Puts both slugcats back at the start and scatters new spears.
    # kills[] is NOT reset, so the score carries over between rounds.
    #   for each chunk i: x, y = start_x[i], start_y[i];  vx = vy = 0
    #   for each player p: move_dir = start_dir[p]; timers/requests = 0;
    #                      held_spear[p] = -1
    #   spawn_spears()
    #-----------------------------------------------------------------------------
reset_round:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $0, %rcx               # rcx = chunk index
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

    movq $0, %rcx               # rcx = player index
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

    call spawn_spears           # see spears.s

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void update_physics(void)
    #
    # Per-frame simulation step:
    #   for each chunk i (player p = i / 2, part = i % 2):
    #       if part == head && move_timer[p] > 0:
    #                             vx += (move_dir[p] * RUN_SPEED - vx) / 4
    #       else:                 vx  = vx * 7 / 8          (friction)
    #       if jump_req[p] && on_ground[p]: vy = -jump_kick[part]
    #       vy = min(vy + GRAVITY, MAX_FALL)
    #       x += vx;  y += vy
    #   for each player p: spine(p)                (pull head + body together)
    #                      move_timer[p]-- (if > 0), jump_req[p] = 0,
    #                      on_ground[p] = 0
    #   for each chunk i: collide_chunk(i)       (sets on_ground[p] again)
    #   update_spears()
    #
    # (grab_or_throw(p) also runs in the player loop when grab_req[p] is set)
    #-----------------------------------------------------------------------------
update_physics:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = chunk index i  (or player index)
    pushq %r12                  # r12 = player index p of chunk i
    pushq %r13                  # r13 = part of chunk i (0 = head, 1 = body)
    subq  $8, %rsp              # keep the stack 16-byte aligned

    #-----------------------------------------------------------------------------
    # 1. Move every chunk
    #-----------------------------------------------------------------------------
    movq $0, %rbx
.move_loop:
    cmpq $NUM_CHUNKS, %rbx
    jge  .move_done

    movq %rbx, %r12
    shrq $1, %r12               # p = i / 2
    movq %rbx, %r13
    andq $1, %r13               # part = i % 2   (lowest bit)

    # only the head runs; the body just slides and gets dragged by the spine
    cmpq $1, %r13
    je   .friction
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
    movq jump_kick(,%r13,8), %rax # head and body get different kicks
    negq %rax                   # negative = up
    movq %rax, chunk_vy(,%rbx,8)
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

    movq %rbx, %rdi
    call spine                  # spine(p)

    cmpq $0, grab_req(,%rbx,8)  # grab/throw pressed?
    je   .no_grab
    movq %rbx, %rdi
    call grab_or_throw          # grab_or_throw(p), see spears.s
    movq $0, grab_req(,%rbx,8)
.no_grab:

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

    #-----------------------------------------------------------------------------
    # 4. Spears (held ones follow the head, thrown ones fly and may kill)
    #-----------------------------------------------------------------------------
    call update_spears

    # epilogue
    addq $8, %rsp
    popq %r13
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void spine(long p /* %rdi */)
    #
    # A spring between player p's head and body. Each frame it fixes 1/5 of the
    # difference between their distance and REST_LEN, so it stretches when
    # yanked and bounces back.
    #   dx = head.x - body.x;   dy = head.y - body.y
    #   d  = isqrt(dx*dx + dy*dy)
    #   if d == 0: return
    #   cx = dx * (d - REST_LEN) / (d * SPINE_DIV)
    #   cy = dy * (d - REST_LEN) / (d * SPINE_DIV)
    #   head.x -= cx; head.vx -= cx;   head.y -= cy; head.vy -= cy
    #   body.x += cx; body.vx += cx;   body.y += cy; body.vy += cy
    # (Changing the velocity too is what makes it springy instead of rigid.)
    #-----------------------------------------------------------------------------
spine:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = head index
    pushq %r12                  # r12 = body index
    pushq %r13                  # r13 = dx
    pushq %r14                  # r14 = dy

    movq %rdi, %rbx
    shlq $1, %rbx               # head = p * 2
    movq %rbx, %r12
    incq %r12                   # body = p * 2 + 1

    movq chunk_x(,%rbx,8), %r13
    subq chunk_x(,%r12,8), %r13 # dx = head.x - body.x
    movq chunk_y(,%rbx,8), %r14
    subq chunk_y(,%r12,8), %r14 # dy = head.y - body.y

    movq %r13, %rdi
    imulq %r13, %rdi            # rdi = dx * dx
    movq %r14, %rax
    imulq %r14, %rax            # rax = dy * dy
    addq %rax, %rdi             # rdi = dx*dx + dy*dy
    call isqrt                  # rax = d

    cmpq $0, %rax               # head exactly on body: no direction, skip
    je   .spine_done

    movq %rax, %r8
    imulq $SPINE_DIV, %r8       # r8 = d * SPINE_DIV        (divisor)
    movq %rax, %r9
    subq $REST_LEN, %r9         # r9 = d - REST_LEN         (how stretched)

    movq %r13, %rax             # cx = dx * (d - REST_LEN) / (d * SPINE_DIV)
    imulq %r9, %rax
    cqto
    idivq %r8
    movq %rax, %r10             # r10 = cx

    movq %r14, %rax             # cy = dy * (d - REST_LEN) / (d * SPINE_DIV)
    imulq %r9, %rax
    cqto
    idivq %r8
    movq %rax, %r11             # r11 = cy

    subq %r10, chunk_x(,%rbx,8) # head moves towards the body...
    subq %r10, chunk_vx(,%rbx,8)
    subq %r11, chunk_y(,%rbx,8)
    subq %r11, chunk_vy(,%rbx,8)
    addq %r10, chunk_x(,%r12,8) # ...and the body towards the head
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

    #-----------------------------------------------------------------------------
    # long isqrt(long n /* %rdi */) -> %rax
    #
    # Integer square root: the biggest r with r * r <= n.
    #   r = 0
    #   while (r + 1) * (r + 1) <= n: r++
    #   return r
    # Slow for huge numbers, but our distances are only ~100, so it's fine.
    #-----------------------------------------------------------------------------
isqrt:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $0, %rax               # r = 0
.isqrt_loop:
    movq %rax, %rcx
    incq %rcx                   # rcx = r + 1
    imulq %rcx, %rcx            # rcx = (r + 1) * (r + 1)
    cmpq %rdi, %rcx
    jg   .isqrt_done            # (r + 1)^2 > n -> r is the answer
    incq %rax                   # r++
    jmp  .isqrt_loop

.isqrt_done:
    # epilogue
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
    # sampler (draw_world), spears are drawn on top, then the HUD text is
    # written over the top row.
    #-----------------------------------------------------------------------------
draw_game:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    call draw_world             # see render.s
    call draw_spears            # see spears.s

    # mvprintw(0, 0, hud_text, kills[0], kills[1])
    movq $0, %rdi               # row
    movq $0, %rsi               # column
    movq $hud_text, %rdx        # format string
    movq kills, %rcx            # first  %ld: kills[0] (P1)
    movq kills+8, %r8           # second %ld: kills[1] (P2), 8 bytes further
    movq $0, %rax               # no float arguments (like printf)
    call mvprintw

    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
