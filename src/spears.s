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

    movq $0, %rbx               # spear s = 0
.ss_loop:
    cmpq $NUM_SPEARS, %rbx      # placed all 6?
    jge  .ss_done

    call rand                   # platform = rand() % NUM_PLATS
    movl %eax, %eax             # rand gives an int, clear the top half
    movq $0, %rdx               # divq divides rdx:rax
    movq $NUM_PLATS, %rcx
    divq %rcx                   # remainder in rdx
    movq %rdx, %r12             # r12 = random platform 0..5

    call rand                   # x = x0 + 16 + rand() % (width - 32)
    movl %eax, %eax
    movq plat_x1(,%r12,8), %rcx
    subq plat_x0(,%r12,8), %rcx # width of the platform
    subq $32, %rcx              # minus 16 on each side, so not right on the edge
    movq $0, %rdx
    divq %rcx                   # rdx = random 0 .. width - 33
    addq plat_x0(,%r12,8), %rdx # + left edge
    addq $16, %rdx              # + the 16 margin
    movq %rdx, spear_x(,%rbx,8)

    movq plat_y0(,%r12,8), %rax # y = top of the platform
    movq %rax, spear_y(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)  # not moving
    movq $0, spear_vy(,%rbx,8)
    movq $SPEAR_STUCK, spear_state(,%rbx,8) # stuck in the ground, grabbable

    incq %rbx                   # next spear
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

    movq held_spear(,%rdi,8), %rcx # rcx = spear we hold, -1 = none
    cmpq $0, %rcx
    jl   .gt_find               # empty hands -> try to grab one

    # throw
    movq $SPEAR_FLYING, spear_state(,%rcx,8)
    movq move_dir(,%rdi,8), %rax # the way we're facing, 1 or -1
    movq %rax, spear_dir(,%rcx,8) # tip points that way
    imulq $SPEAR_SPEED, %rax    # vx = dir * SPEAR_SPEED
    movq %rax, spear_vx(,%rcx,8) # 56 or -56, fast and flat
    movq $-SPEAR_LIFT, spear_vy(,%rcx,8) # a bit upwards
    movq $-1, held_spear(,%rdi,8) # hands empty again
    jmp  .gt_done

.gt_find:
    movq %rdi, %r8
    shlq $1, %r8
    incq %r8                    # body chunk = p * 2 + 1 (the body is at the feet)

    movq $0, %rcx               # spear s = 0
.gt_loop:
    cmpq $NUM_SPEARS, %rcx      # checked all spears?
    jge  .gt_done               #   none close enough, nothing happens

    cmpq $SPEAR_STUCK, spear_state(,%rcx,8) # only spears in the ground
    jne  .gt_next               # (held / flying ones can't be grabbed)

    movq spear_x(,%rcx,8), %rax # |spear x - body x| < GRAB_RANGE_X
    subq chunk_x(,%r8,8), %rax
    cmpq $0, %rax               # negative?
    jge  .gt_abs_x
    negq %rax                   #   flip it, that's the absolute value
.gt_abs_x:
    cmpq $GRAB_RANGE_X, %rax    # within 48 (3 cells) sideways?
    jge  .gt_next

    movq spear_y(,%rcx,8), %rax # |spear y - body y| < GRAB_RANGE_Y
    subq chunk_y(,%r8,8), %rax
    cmpq $0, %rax
    jge  .gt_abs_y
    negq %rax
.gt_abs_y:
    cmpq $GRAB_RANGE_Y, %rax    # within 96 up/down? (so same platform)
    jge  .gt_next

    movq $SPEAR_HELD, spear_state(,%rcx,8) # close enough, pick it up
    movq %rdi, spear_owner(,%rcx,8) # it's ours now
    movq %rcx, held_spear(,%rdi,8)  # remember which one we hold
    jmp  .gt_done

.gt_next:
    incq %rcx                   # next spear
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

    movq $0, %rbx               # spear s = 0
.us_loop:
    cmpq $NUM_SPEARS, %rbx      # done all spears?
    jge  .us_done

    cmpq $SPEAR_HELD, spear_state(,%rbx,8)
    je   .us_held
    cmpq $SPEAR_FLYING, spear_state(,%rbx,8)
    je   .us_flying
    jmp  .us_next               # stuck, nothing to do

.us_held:
    movq spear_owner(,%rbx,8), %rax # rax = who holds it
    movq move_dir(,%rax,8), %rcx
    movq %rcx, spear_dir(,%rbx,8) # point where they face
    shlq $1, %rax               # owner's head chunk
    movq chunk_x(,%rax,8), %rcx
    movq %rcx, spear_x(,%rbx,8) # sit on their head
    movq chunk_y(,%rax,8), %rcx
    movq %rcx, spear_y(,%rbx,8)
    jmp  .us_next

.us_flying:
    addq $SPEAR_GRAVITY, spear_vy(,%rbx,8) # gravity 1 (slugcats get 5),
    cmpq $SPEAR_MAX_FALL, spear_vy(,%rbx,8) # so the arc stays flat
    jle  .us_no_cap
    movq $SPEAR_MAX_FALL, spear_vy(,%rbx,8) # max 24, thinner than a platform
.us_no_cap:                     # so it can't fall through one in a frame

    movq spear_vx(,%rbx,8), %rax # x += vx
    addq %rax, spear_x(,%rbx,8)
    movq spear_vy(,%rbx,8), %rax # y += vy
    addq %rax, spear_y(,%rbx,8)

    cmpq $0, spear_x(,%rbx,8)   # hit a side: stop going sideways, just drop
    jge  .us_right
    movq $0, spear_x(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)
.us_right:
    cmpq $WORLD_W - 1, spear_x(,%rbx,8) # same for the right side
    jle  .us_edges_done
    movq $WORLD_W - 1, spear_x(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)
.us_edges_done:

    movq spear_x(,%rbx,8), %rdi # find_platform(x: spear x, y: spear y)
    movq spear_y(,%rbx,8), %rsi # (rdi/rsi are also used for the hit test below)

    cmpq $0, spear_vy(,%rbx,8)  # only sticks while falling, like the slugcats
    jl   .us_players
    call find_platform          # render.s, rax = platform or -1
    cmpq $0, %rax
    jl   .us_players            # in the air -> check if it hits someone

    movq plat_y0(,%rax,8), %rcx # stick in: y = platform top
    movq %rcx, spear_y(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)  # stop
    movq $0, spear_vy(,%rbx,8)
    movq $SPEAR_STUCK, spear_state(,%rbx,8) # can be picked up again
    jmp  .us_next

.us_players:
    movq $0, %rcx               # chunk
.us_hit_loop:
    cmpq $NUM_CHUNKS, %rcx      # checked all 4 circles?
    jge  .us_next

    movq %rcx, %rax
    shrq $1, %rax               # player of this chunk
    cmpq spear_owner(,%rbx,8), %rax
    je   .us_next_chunk         # can't hit yourself

    movq %rdi, %r8              # inside the circle? d2 < r2
    subq chunk_x(,%rcx,8), %r8  # dx
    imulq %r8, %r8              # dx * dx
    movq %rsi, %r9
    subq chunk_y(,%rcx,8), %r9  # dy
    imulq %r9, %r9              # dy * dy
    addq %r9, %r8               # d2 (same test as sample_point in render.s)
    movq chunk_r(,%rcx,8), %r10
    imulq %r10, %r10            # r2
    cmpq %r10, %r8
    jge  .us_next_chunk         # missed this circle

    movq spear_owner(,%rbx,8), %rax # hit! thrower wins the round
    movq %rax, winner
    incq kills(,%rax,8)         # +1 point
    movq $SCENE_END, game_state # main.s stops the physics -> frozen end screen
    jmp  .us_next

.us_next_chunk:
    incq %rcx                   # next circle
    jmp  .us_hit_loop

.us_next:
    incq %rbx                   # next spear
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

    movq $0, %rbx               # spear s = 0
.ds_loop:
    cmpq $NUM_SPEARS, %rbx      # drawn all spears?
    jge  .ds_done

    movq spear_y(,%rbx,8), %r12
    shrq $5, %r12               # / 32, subunits -> screen row
    movq spear_x(,%rbx,8), %r13
    shrq $4, %r13               # / 16, subunits -> screen column

    cmpq $SPEAR_STUCK, spear_state(,%rbx,8) # in the ground -> upright
    jne  .ds_flat               # otherwise lying flat

    movq $1, %r14               # '|' on the 3 rows above
.ds_up_loop:
    cmpq $3, %r14               # drawn 3 already?
    jg   .ds_next
    movq %r12, %rdi             # mvaddch(row: row - k, col: col, ch: '|')
    subq %r14, %rdi             # k rows above the platform top
    movq %r13, %rsi
    movq $'|', %rdx
    call mvaddch
    incq %r14                   # next row up
    jmp  .ds_up_loop

.ds_flat:
    movq $-2, %r14              # '-' from col - 2 to col + 2
.ds_flat_loop:
    cmpq $2, %r14               # drawn all 5?
    jg   .ds_tip
    movq %r12, %rdi             # mvaddch(row: row, col: col + k, ch: '-')
    movq %r13, %rsi
    addq %r14, %rsi
    movq $'-', %rdx
    call mvaddch
    incq %r14                   # next one to the right
    jmp  .ds_flat_loop

.ds_tip:
    movq %r12, %rdi             # same row for the tip
    cmpq $1, spear_dir(,%rbx,8) # pointing right?
    jne  .ds_tip_left
    movq %r13, %rsi             # mvaddch(row: row, col: col + 2, ch: '>')
    addq $2, %rsi
    movq $'>', %rdx             # overwrites the last '-', gives "---->"
    call mvaddch
    jmp  .ds_next
.ds_tip_left:
    movq %r13, %rsi             # mvaddch(row: row, col: col - 2, ch: '<')
    subq $2, %rsi
    movq $'<', %rdx             # overwrites the first '-', gives "<----"
    call mvaddch

.ds_next:
    incq %rbx                   # next spear
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
