# render.s - the brightness sampler, turns the world into ascii
#
# every cell gets tested at 8 points (2 across, 4 down). each point asks
# "how bright is the world here" (0..9), we average them and pick that char
# from " .:-=+*#%@". half-covered cells get dimmer chars, so shapes look smooth.

    .include "constants.inc"

    .text
    .globl draw_world
    .globl sample_point
    .globl find_platform

# void draw_world(void)
#   for each row, col:
#       sum = sample_point() at the 8 points in the cell
#       index = (sum + 4) / 8                    rounded average
#       if index == 0: index = sky_shade(col, row)
#       mvaddch(row, col, ramp[index] | COLOR_PAIR(cell_owner))
draw_world:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # sx
    pushq %r12                  # row
    pushq %r13                  # col
    pushq %r14                  # sum
    pushq %r15                  # sy
    subq  $8, %rsp              # stack aligned for mvaddch

    movq $0, %r12
.row_loop:
    cmpq $ROWS, %r12
    jge  .rows_done

    movq $0, %r13
.col_loop:
    cmpq $COLS, %r13
    jge  .next_row

    movq $0, %r14
    movq $0, cell_owner         # sample_point sets it if it sees something coloured

    movq $0, %r15
.sy_loop:
    cmpq $SUB_Y, %r15
    jge  .samples_done

    movq $0, %rbx
.sx_loop:
    cmpq $SUB_X, %rbx
    jge  .next_sy

    # sample_point(x: col*CELL_W + sx*SAMPLE_STEP + SAMPLE_OFF,
    #              y: row*CELL_H + sy*SAMPLE_STEP + SAMPLE_OFF)
    movq %r13, %rdi
    imulq $CELL_W, %rdi
    movq %rbx, %rax
    imulq $SAMPLE_STEP, %rax
    addq %rax, %rdi
    addq $SAMPLE_OFF, %rdi

    # y = row * CELL_H + sy * SAMPLE_STEP + SAMPLE_OFF
    movq %r12, %rsi
    imulq $CELL_H, %rsi
    movq %r15, %rax
    imulq $SAMPLE_STEP, %rax
    addq %rax, %rsi
    addq $SAMPLE_OFF, %rsi

    call sample_point
    addq %rax, %r14

    incq %rbx
    jmp  .sx_loop
.next_sy:
    incq %r15
    jmp  .sy_loop

.samples_done:
    addq $4, %r14               # (sum + 4) / 8
    shrq $3, %r14

    cmpq $0, %r14               # empty -> sky
    jne  .have_index
    movq %r13, %rdi             # sky_shade(col: col, row: row)
    movq %r12, %rsi
    call sky_shade              # sky.s, gives 0, 1 or 2
    movq %rax, %r14
    movq $SKY_PAIR, cell_owner
.have_index:

    movzbq ramp(%r14), %rdx     # the char
    movq cell_owner, %rax
    shlq $8, %rax               # COLOR_PAIR(n) is just n << 8
    orq  %rax, %rdx

    movq %r12, %rdi             # mvaddch(row: row, col: col, ch: char | colour)
    movq %r13, %rsi
    call mvaddch

    incq %r13
    jmp  .col_loop
.next_row:
    incq %r12
    jmp  .row_loop

.rows_done:
    # epilogue
    addq $8, %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

# long sample_point(long x /* %rdi */, long y /* %rsi */) -> %rax (0..9)
#   inside a platform           -> TERRAIN_SHADE
#   in a platform's wet film     -> WATER_SHADE
#   under the lake surface      -> WATER_SHADE
#   inside a chunk circle        -> 9 / 8 / 6 (centre / middle / edge)
# the brightest one wins. uses squared distances so no sqrt.
sample_point:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $0, %r10               # brightness so far

    # platforms
    call find_platform          # find_platform(x: x, y: y), already in rdi/rsi
                                # rax = platform or -1, rdi/rsi untouched
    cmpq $0, %rax
    jl   .sp_films
    movq $TERRAIN_SHADE, %r10

    # wet film on top of platforms (not the floor, that gets the lake)
.sp_films:
    movq $1, %rcx
.sp_film_loop:
    cmpq $NUM_PLATS, %rcx
    jge  .sp_lake

    cmpq plat_x0(,%rcx,8), %rdi # x outside -> skip
    jl   .sp_next_film
    cmpq plat_x1(,%rcx,8), %rdi
    jge  .sp_next_film
    cmpq plat_y0(,%rcx,8), %rsi # below the top -> not the film
    jge  .sp_next_film
    movq plat_wet(,%rcx,8), %r8
    shrq $3, %r8                # film height = plat_wet / 8
    movq plat_y0(,%rcx,8), %r9
    subq %r8, %r9               # top of the film
    cmpq %r9, %rsi
    jl   .sp_next_film          # above the film

    cmpq $WATER_SHADE, %r10     # make it water, unless something brighter
    jge  .sp_next_film          # is already here
    movq $WATER_SHADE, %r10
    cmpq $0, cell_owner         # don't paint a slugcat cell blue
    jne  .sp_next_film
    movq $WATER_PAIR, cell_owner
.sp_next_film:
    incq %rcx
    jmp  .sp_film_loop

    # the lake
.sp_lake:
    movq $FLOOR_TOP, %r8
    subq water_level, %r8       # surface
    cmpq %r8, %rsi
    jl   .sp_chunks
    cmpq $WATER_SHADE, %r10     # make it water, unless something brighter
    jge  .sp_chunks             # is already here
    movq $WATER_SHADE, %r10
    cmpq $0, cell_owner         # don't paint a slugcat cell blue
    jne  .sp_chunks
    movq $WATER_PAIR, cell_owner

    # the slugcats
.sp_chunks:
    movq $0, %rcx
.sp_chunk_loop:
    cmpq $NUM_CHUNKS, %rcx
    jge  .sp_done

    movq %rdi, %r8
    subq chunk_x(,%rcx,8), %r8
    imulq %r8, %r8              # dx * dx
    movq %rsi, %r9
    subq chunk_y(,%rcx,8), %r9
    imulq %r9, %r9              # dy * dy
    addq %r9, %r8               # r8 = d2
    movq chunk_r(,%rcx,8), %r9
    imulq %r9, %r9              # r9 = r2

    cmpq %r9, %r8
    jge  .sp_next_chunk         # outside

    movq $6, %r11               # edge
    shlq $1, %r8                # d2 * 2
    cmpq %r9, %r8
    jge  .sp_have_shade
    movq $8, %r11               # middle (d < 0.71 r)
    shlq $1, %r8                # d2 * 4
    cmpq %r9, %r8
    jge  .sp_have_shade
    movq $9, %r11               # centre (d < r / 2)
.sp_have_shade:

    cmpq %r10, %r11
    jle  .sp_next_chunk         # not brighter
    movq %r11, %r10
    movq %rcx, %r8
    shrq $1, %r8                # player = chunk / 2
    incq %r8                    # colour pair = player + 1
    movq %r8, cell_owner

.sp_next_chunk:
    incq %rcx
    jmp  .sp_chunk_loop

.sp_done:
    movq %r10, %rax
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

# long find_platform(long x /* %rdi */, long y /* %rsi */) -> %rax
# which platform is (x, y) inside? -1 if none.
# only touches rax and rcx, so rdi/rsi are still x, y after the call.
find_platform:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $-1, %rax              # not found (yet)
    movq $0, %rcx
.fp_loop:
    cmpq $NUM_PLATS, %rcx
    jge  .fp_done

    cmpq plat_x0(,%rcx,8), %rdi
    jl   .fp_next
    cmpq plat_x1(,%rcx,8), %rdi
    jge  .fp_next
    cmpq plat_y0(,%rcx,8), %rsi
    jl   .fp_next
    cmpq plat_y1(,%rcx,8), %rsi
    jge  .fp_next

    movq %rcx, %rax             # found it
    jmp  .fp_done

.fp_next:
    incq %rcx
    jmp  .fp_loop

.fp_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
