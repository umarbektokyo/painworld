    #=============================================================================
    # painworld — src/spears.s
    # Spears: spawn on platforms, pick up, throw, fly, stick, kill.
    #
    # Every spear is in one of three states (spear_state):
    #   SPEAR_STUCK   standing upright in a platform; walk over it and grab it
    #   SPEAR_HELD    carried at the owner's head, pointing where they face
    #   SPEAR_FLYING  thrown: flies sideways in a shallow arc until it hits a
    #                 platform (-> STUCK) or the other slugcat (-> round over)
    #=============================================================================

    .include "constants.inc"

    .text
    .globl spawn_spears
    .globl grab_or_throw
    .globl update_spears
    .globl draw_spears

    #-----------------------------------------------------------------------------
    # void spawn_spears(void)
    #
    #   for each spear s:
    #       j = rand() % NUM_PLATS                          (random platform)
    #       x = plat_x0[j] + 16 + rand() % (width - 32)     (random spot on it)
    #       y = plat_y0[j];  state = STUCK
    #-----------------------------------------------------------------------------
spawn_spears:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = spear index s
    pushq %r12                  # r12 = platform index j

    movq $0, %rbx
.ss_loop:
    cmpq $NUM_SPEARS, %rbx
    jge  .ss_done

    # j = rand() % NUM_PLATS
    call rand                   # eax = random number
    movl %eax, %eax             # clear the top half of rax (rand returns int)
    movq $0, %rdx               # divq divides rdx:rax, so rdx must be 0
    movq $NUM_PLATS, %rcx
    divq %rcx                   # rdx = rax % NUM_PLATS
    movq %rdx, %r12

    # x = plat_x0[j] + 16 + rand() % (plat_x1[j] - plat_x0[j] - 32)
    call rand
    movl %eax, %eax
    movq plat_x1(,%r12,8), %rcx
    subq plat_x0(,%r12,8), %rcx
    subq $32, %rcx              # keep 16 subunits away from both edges
    movq $0, %rdx
    divq %rcx                   # rdx = rand % (width - 32)
    addq plat_x0(,%r12,8), %rdx
    addq $16, %rdx
    movq %rdx, spear_x(,%rbx,8)

    movq plat_y0(,%r12,8), %rax # y = top of the platform
    movq %rax, spear_y(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)
    movq $0, spear_vy(,%rbx,8)
    movq $SPEAR_STUCK, spear_state(,%rbx,8)

    incq %rbx
    jmp  .ss_loop

.ss_done:
    # epilogue
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void grab_or_throw(long p /* %rdi */)
    #
    #   if held_spear[p] >= 0:                         (holding one -> throw)
    #       s = held_spear[p];  state[s] = FLYING
    #       vx = move_dir[p] * SPEAR_SPEED;  vy = -SPEAR_LIFT
    #       held_spear[p] = -1
    #   else:                                          (empty hands -> grab)
    #       for each spear s that is STUCK:
    #           if |spear_x - body.x| < GRAB_RANGE_X && |spear_y - body.y| < GRAB_RANGE_Y:
    #               state[s] = HELD;  owner[s] = p;  held_spear[p] = s;  return
    #-----------------------------------------------------------------------------
grab_or_throw:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq held_spear(,%rdi,8), %rcx  # rcx = spear we hold (or -1)
    cmpq $0, %rcx
    jl   .gt_find

    # throw
    movq $SPEAR_FLYING, spear_state(,%rcx,8)
    movq move_dir(,%rdi,8), %rax
    movq %rax, spear_dir(,%rcx,8)
    imulq $SPEAR_SPEED, %rax    # vx = move_dir * SPEAR_SPEED
    movq %rax, spear_vx(,%rcx,8)
    movq $-SPEAR_LIFT, spear_vy(,%rcx,8)
    movq $-1, held_spear(,%rdi,8)
    jmp  .gt_done

.gt_find:
    movq %rdi, %r8
    shlq $1, %r8
    incq %r8                    # r8 = body chunk = p * 2 + 1

    movq $0, %rcx               # rcx = spear index
.gt_loop:
    cmpq $NUM_SPEARS, %rcx
    jge  .gt_done

    cmpq $SPEAR_STUCK, spear_state(,%rcx,8)
    jne  .gt_next

    movq spear_x(,%rcx,8), %rax # rax = |spear_x - body.x|
    subq chunk_x(,%r8,8), %rax
    cmpq $0, %rax
    jge  .gt_abs_x
    negq %rax
.gt_abs_x:
    cmpq $GRAB_RANGE_X, %rax
    jge  .gt_next

    movq spear_y(,%rcx,8), %rax # rax = |spear_y - body.y|
    subq chunk_y(,%r8,8), %rax
    cmpq $0, %rax
    jge  .gt_abs_y
    negq %rax
.gt_abs_y:
    cmpq $GRAB_RANGE_Y, %rax
    jge  .gt_next

    # close enough: pick it up
    movq $SPEAR_HELD, spear_state(,%rcx,8)
    movq %rdi, spear_owner(,%rcx,8)
    movq %rcx, held_spear(,%rdi,8)
    jmp  .gt_done

.gt_next:
    incq %rcx
    jmp  .gt_loop

.gt_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void update_spears(void)
    #
    #   for each spear s:
    #     HELD:   x, y = owner's head;  dir = move_dir[owner]
    #     FLYING: vy = min(vy + SPEAR_GRAVITY, SPEAR_MAX_FALL)
    #             x += vx;  y += vy
    #             hit the left / right edge -> stop moving sideways, drop down
    #             falling into a platform   -> y = top;  state = STUCK
    #             inside a chunk of the other player ->
    #                 winner = owner;  kills[owner]++;  game_state = SCENE_END
    #-----------------------------------------------------------------------------
update_spears:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = spear index s
    subq  $8, %rsp              # keep the stack 16-byte aligned

    movq $0, %rbx
.us_loop:
    cmpq $NUM_SPEARS, %rbx
    jge  .us_done

    cmpq $SPEAR_HELD, spear_state(,%rbx,8)
    je   .us_held
    cmpq $SPEAR_FLYING, spear_state(,%rbx,8)
    je   .us_flying
    jmp  .us_next               # STUCK: nothing to do

    #-----------------------------------------------------------------------------
    # held: follow the owner's head
    #-----------------------------------------------------------------------------
.us_held:
    movq spear_owner(,%rbx,8), %rax
    movq move_dir(,%rax,8), %rcx
    movq %rcx, spear_dir(,%rbx,8)   # point where the owner faces
    shlq $1, %rax                   # rax = owner's head chunk
    movq chunk_x(,%rax,8), %rcx
    movq %rcx, spear_x(,%rbx,8)
    movq chunk_y(,%rax,8), %rcx
    movq %rcx, spear_y(,%rbx,8)
    jmp  .us_next

    #-----------------------------------------------------------------------------
    # flying
    #-----------------------------------------------------------------------------
.us_flying:
    # gravity, capped
    addq $SPEAR_GRAVITY, spear_vy(,%rbx,8)
    cmpq $SPEAR_MAX_FALL, spear_vy(,%rbx,8)
    jle  .us_no_cap
    movq $SPEAR_MAX_FALL, spear_vy(,%rbx,8)
.us_no_cap:

    # x += vx;  y += vy
    movq spear_vx(,%rbx,8), %rax
    addq %rax, spear_x(,%rbx,8)
    movq spear_vy(,%rbx,8), %rax
    addq %rax, spear_y(,%rbx,8)

    # left / right edge: stop sideways movement, it just drops
    cmpq $0, spear_x(,%rbx,8)
    jge  .us_right
    movq $0, spear_x(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)
.us_right:
    cmpq $WORLD_W - 1, spear_x(,%rbx,8)
    jle  .us_edges_done
    movq $WORLD_W - 1, spear_x(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)
.us_edges_done:

    movq spear_x(,%rbx,8), %rdi # rdi, rsi = the spear's point
    movq spear_y(,%rbx,8), %rsi

    # platforms (only while falling, like the slugcats)
    cmpq $0, spear_vy(,%rbx,8)
    jl   .us_players
    movq $0, %rcx               # rcx = platform index
.us_plat_loop:
    cmpq $NUM_PLATS, %rcx
    jge  .us_players

    cmpq plat_x0(,%rcx,8), %rdi
    jl   .us_next_plat
    cmpq plat_x1(,%rcx,8), %rdi
    jge  .us_next_plat
    cmpq plat_y0(,%rcx,8), %rsi
    jl   .us_next_plat
    cmpq plat_y1(,%rcx,8), %rsi
    jge  .us_next_plat

    # stick into the platform
    movq plat_y0(,%rcx,8), %rax
    movq %rax, spear_y(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)
    movq $0, spear_vy(,%rbx,8)
    movq $SPEAR_STUCK, spear_state(,%rbx,8)
    jmp  .us_next

.us_next_plat:
    incq %rcx
    jmp  .us_plat_loop

    # slugcats (same circle test as sample_point in render.s)
.us_players:
    movq $0, %rcx               # rcx = chunk index
.us_hit_loop:
    cmpq $NUM_CHUNKS, %rcx
    jge  .us_next

    movq %rcx, %rax
    shrq $1, %rax               # rax = player of this chunk
    cmpq spear_owner(,%rbx,8), %rax
    je   .us_next_chunk         # can't hit yourself

    movq %rdi, %r8
    subq chunk_x(,%rcx,8), %r8
    imulq %r8, %r8              # r8 = dx * dx
    movq %rsi, %r9
    subq chunk_y(,%rcx,8), %r9
    imulq %r9, %r9              # r9 = dy * dy
    addq %r9, %r8               # r8 = d2
    movq chunk_r(,%rcx,8), %r10
    imulq %r10, %r10            # r10 = r2
    cmpq %r10, %r8
    jge  .us_next_chunk         # missed this chunk

    # hit! the thrower wins the round
    movq spear_owner(,%rbx,8), %rax
    movq %rax, winner
    incq kills(,%rax,8)
    movq $SCENE_END, game_state
    jmp  .us_next

.us_next_chunk:
    incq %rcx
    jmp  .us_hit_loop

.us_next:
    incq %rbx
    jmp  .us_loop

.us_done:
    # epilogue
    addq $8, %rsp
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

    #-----------------------------------------------------------------------------
    # void draw_spears(void)
    #
    # Drawn on top of the world as plain characters (row = y / 32, col = x / 16):
    #   STUCK:          3 '|' straight up from the platform
    #   HELD / FLYING:  "---->" (or "<----") centred on the spear
    # mvaddch ignores anything outside the screen, so no bounds checks needed.
    #-----------------------------------------------------------------------------
draw_spears:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = spear index s
    pushq %r12                  # r12 = row
    pushq %r13                  # r13 = col
    pushq %r14                  # r14 = loop counter k

    movq $0, %rbx
.ds_loop:
    cmpq $NUM_SPEARS, %rbx
    jge  .ds_done

    movq spear_y(,%rbx,8), %r12
    shrq $5, %r12               # row = y / 32
    movq spear_x(,%rbx,8), %r13
    shrq $4, %r13               # col = x / 16

    cmpq $SPEAR_STUCK, spear_state(,%rbx,8)
    jne  .ds_flat

    # upright: '|' on the 3 rows above the platform
    movq $1, %r14               # k = 1
.ds_up_loop:
    cmpq $3, %r14
    jg   .ds_next
    movq %r12, %rdi
    subq %r14, %rdi             # row - k
    movq %r13, %rsi
    movq $'|', %rdx
    call mvaddch
    incq %r14
    jmp  .ds_up_loop

    # flat: '-' from col - 2 to col + 2, then the tip on the front end
.ds_flat:
    movq $-2, %r14              # k = -2
.ds_flat_loop:
    cmpq $2, %r14
    jg   .ds_tip
    movq %r12, %rdi
    movq %r13, %rsi
    addq %r14, %rsi             # col + k
    movq $'-', %rdx
    call mvaddch
    incq %r14
    jmp  .ds_flat_loop

.ds_tip:
    movq %r12, %rdi
    cmpq $1, spear_dir(,%rbx,8)
    jne  .ds_tip_left
    movq %r13, %rsi
    addq $2, %rsi
    movq $'>', %rdx             # pointing right: tip at col + 2
    call mvaddch
    jmp  .ds_next
.ds_tip_left:
    movq %r13, %rsi
    subq $2, %rsi
    movq $'<', %rdx             # pointing left: tip at col - 2
    call mvaddch

.ds_next:
    incq %rbx
    jmp  .ds_loop

.ds_done:
    # epilogue
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret
