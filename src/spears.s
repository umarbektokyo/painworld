# spear spawn, pick up, throw, fly, stick, kill
#
# a spear is always in one of 3 states:
#   STUCK   upright in a platform, walk onto it to grab it
#   HELD    follows the owner's head, points where they face
#   FLYING  thrown, flies in a flat arc until it hits a platform (then STUCK)
#           or the other slugcat (then round over)

    .include "constants.inc"

    .text
    .globl spawn_spears
    .globl grab_or_throw
    .globl update_spears
    .globl draw_spears

# void spawn_spears(void)
# each spear goes to a random platform at a random x (16 away from the edges)
spawn_spears:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # spear
    pushq %r12                  # platform

    movq $0, %rbx
.ss_loop:
    cmpq $NUM_SPEARS, %rbx
    jge  .ss_done

    call rand                   # platform = rand() % NUM_PLATS
    movl %eax, %eax             # rand gives an int, clear the top half
    movq $0, %rdx               # divq divides rdx:rax
    movq $NUM_PLATS, %rcx
    divq %rcx                   # remainder in rdx
    movq %rdx, %r12

    call rand                   # x = x0 + 16 + rand() % (width - 32)
    movl %eax, %eax
    movq plat_x1(,%r12,8), %rcx
    subq plat_x0(,%r12,8), %rcx
    subq $32, %rcx
    movq $0, %rdx
    divq %rcx
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

# void grab_or_throw(long p /* %rdi */)
# holding one -> throw it. empty hands -> grab a STUCK spear close to our body.
grab_or_throw:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq held_spear(,%rdi,8), %rcx
    cmpq $0, %rcx
    jl   .gt_find

    # throw
    movq $SPEAR_FLYING, spear_state(,%rcx,8)
    movq move_dir(,%rdi,8), %rax
    movq %rax, spear_dir(,%rcx,8)
    imulq $SPEAR_SPEED, %rax    # vx = dir * SPEAR_SPEED
    movq %rax, spear_vx(,%rcx,8)
    movq $-SPEAR_LIFT, spear_vy(,%rcx,8) # a bit upwards
    movq $-1, held_spear(,%rdi,8)
    jmp  .gt_done

.gt_find:
    movq %rdi, %r8
    shlq $1, %r8
    incq %r8                    # body chunk = p * 2 + 1

    movq $0, %rcx
.gt_loop:
    cmpq $NUM_SPEARS, %rcx
    jge  .gt_done

    cmpq $SPEAR_STUCK, spear_state(,%rcx,8)
    jne  .gt_next

    movq spear_x(,%rcx,8), %rax # |spear x - body x| < GRAB_RANGE_X
    subq chunk_x(,%r8,8), %rax
    cmpq $0, %rax
    jge  .gt_abs_x
    negq %rax
.gt_abs_x:
    cmpq $GRAB_RANGE_X, %rax
    jge  .gt_next

    movq spear_y(,%rcx,8), %rax # |spear y - body y| < GRAB_RANGE_Y
    subq chunk_y(,%r8,8), %rax
    cmpq $0, %rax
    jge  .gt_abs_y
    negq %rax
.gt_abs_y:
    cmpq $GRAB_RANGE_Y, %rax
    jge  .gt_next

    movq $SPEAR_HELD, spear_state(,%rcx,8) # close enough, pick it up
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

# void update_spears(void)
#   HELD:   copy the owner's head position + facing
#   FLYING: gravity, move, edges, stick into platforms, hit the other player
update_spears:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # spear
    subq  $8, %rsp              # stack aligned

    movq $0, %rbx
.us_loop:
    cmpq $NUM_SPEARS, %rbx
    jge  .us_done

    cmpq $SPEAR_HELD, spear_state(,%rbx,8)
    je   .us_held
    cmpq $SPEAR_FLYING, spear_state(,%rbx,8)
    je   .us_flying
    jmp  .us_next               # stuck, nothing to do

.us_held:
    movq spear_owner(,%rbx,8), %rax
    movq move_dir(,%rax,8), %rcx
    movq %rcx, spear_dir(,%rbx,8)
    shlq $1, %rax               # owner's head chunk
    movq chunk_x(,%rax,8), %rcx
    movq %rcx, spear_x(,%rbx,8)
    movq chunk_y(,%rax,8), %rcx
    movq %rcx, spear_y(,%rbx,8)
    jmp  .us_next

.us_flying:
    addq $SPEAR_GRAVITY, spear_vy(,%rbx,8)
    cmpq $SPEAR_MAX_FALL, spear_vy(,%rbx,8)
    jle  .us_no_cap
    movq $SPEAR_MAX_FALL, spear_vy(,%rbx,8)
.us_no_cap:

    movq spear_vx(,%rbx,8), %rax
    addq %rax, spear_x(,%rbx,8)
    movq spear_vy(,%rbx,8), %rax
    addq %rax, spear_y(,%rbx,8)

    cmpq $0, spear_x(,%rbx,8)   # hit a side: stop going sideways, just drop
    jge  .us_right
    movq $0, spear_x(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)
.us_right:
    cmpq $WORLD_W - 1, spear_x(,%rbx,8)
    jle  .us_edges_done
    movq $WORLD_W - 1, spear_x(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)
.us_edges_done:

    movq spear_x(,%rbx,8), %rdi # find_platform(x: spear x, y: spear y)
    movq spear_y(,%rbx,8), %rsi

    cmpq $0, spear_vy(,%rbx,8)  # only sticks while falling, like the slugcats
    jl   .us_players
    call find_platform          # render.s, rax = platform or -1
    cmpq $0, %rax
    jl   .us_players

    movq plat_y0(,%rax,8), %rcx # stick in: y = platform top
    movq %rcx, spear_y(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)
    movq $0, spear_vy(,%rbx,8)
    movq $SPEAR_STUCK, spear_state(,%rbx,8)
    jmp  .us_next

.us_players:
    movq $0, %rcx               # chunk
.us_hit_loop:
    cmpq $NUM_CHUNKS, %rcx
    jge  .us_next

    movq %rcx, %rax
    shrq $1, %rax               # player of this chunk
    cmpq spear_owner(,%rbx,8), %rax
    je   .us_next_chunk         # can't hit yourself

    movq %rdi, %r8              # inside the circle? d2 < r2
    subq chunk_x(,%rcx,8), %r8
    imulq %r8, %r8
    movq %rsi, %r9
    subq chunk_y(,%rcx,8), %r9
    imulq %r9, %r9
    addq %r9, %r8
    movq chunk_r(,%rcx,8), %r10
    imulq %r10, %r10
    cmpq %r10, %r8
    jge  .us_next_chunk

    movq spear_owner(,%rbx,8), %rax # hit! thrower wins the round
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

# void draw_spears(void)
# plain chars on top of the world (row = y / 32, col = x / 16):
#   STUCK -> 3 '|' going up,  HELD / FLYING -> "---->" or "<----"
# mvaddch just ignores stuff off screen, so no bounds checks
draw_spears:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # spear
    pushq %r12                  # row
    pushq %r13                  # col
    pushq %r14                  # k

    movq $0, %rbx
.ds_loop:
    cmpq $NUM_SPEARS, %rbx
    jge  .ds_done

    movq spear_y(,%rbx,8), %r12
    shrq $5, %r12               # / 32
    movq spear_x(,%rbx,8), %r13
    shrq $4, %r13               # / 16

    cmpq $SPEAR_STUCK, spear_state(,%rbx,8)
    jne  .ds_flat

    movq $1, %r14               # '|' on the 3 rows above
.ds_up_loop:
    cmpq $3, %r14
    jg   .ds_next
    movq %r12, %rdi             # mvaddch(row: row - k, col: col, ch: '|')
    subq %r14, %rdi
    movq %r13, %rsi
    movq $'|', %rdx
    call mvaddch
    incq %r14
    jmp  .ds_up_loop

.ds_flat:
    movq $-2, %r14              # '-' from col - 2 to col + 2
.ds_flat_loop:
    cmpq $2, %r14
    jg   .ds_tip
    movq %r12, %rdi             # mvaddch(row: row, col: col + k, ch: '-')
    movq %r13, %rsi
    addq %r14, %rsi
    movq $'-', %rdx
    call mvaddch
    incq %r14
    jmp  .ds_flat_loop

.ds_tip:
    movq %r12, %rdi
    cmpq $1, spear_dir(,%rbx,8)
    jne  .ds_tip_left
    movq %r13, %rsi             # mvaddch(row: row, col: col + 2, ch: '>')
    addq $2, %rsi
    movq $'>', %rdx
    call mvaddch
    jmp  .ds_next
.ds_tip_left:
    movq %r13, %rsi             # mvaddch(row: row, col: col - 2, ch: '<')
    subq $2, %rsi
    movq $'<', %rdx
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
