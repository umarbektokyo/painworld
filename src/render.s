    #=============================================================================
    # painworld — src/render.s
    # The brightness sampler: turns the world (circles + rectangles) into ASCII.
    #
    # For every one of the 80 x 24 cells we test 8 points inside the cell
    # (2 across, 4 down), ask "how bright is the world here?" (0..9), take the
    # average, and pick that character from the ramp " .:-=+*#%@".
    # A cell that is only partly covered by a circle gets a dimmer character,
    # which is what makes the shapes look smooth as they move.
    #=============================================================================

    .include "constants.inc"

    .text
    .globl draw_world
    .globl sample_point

    #-----------------------------------------------------------------------------
    # void draw_world(void)
    #
    #   for row in 0..ROWS-1:
    #       for col in 0..COLS-1:
    #           sum = 0;  cell_owner = 0
    #           for sy in 0..SUB_Y-1:
    #               for sx in 0..SUB_X-1:
    #                   x = col * CELL_W + sx * SAMPLE_STEP + SAMPLE_OFF
    #                   y = row * CELL_H + sy * SAMPLE_STEP + SAMPLE_OFF
    #                   sum += sample_point(x, y)
    #           index = (sum + 4) / 8                  (average, rounded)
    #           if index == 0: index = sky_shade(col, row)  (empty: sky)
    #           mvaddch(row, col, ramp[index] | COLOR_PAIR(cell_owner))
    #-----------------------------------------------------------------------------
draw_world:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = sx
    pushq %r12                  # r12 = row
    pushq %r13                  # r13 = col
    pushq %r14                  # r14 = sum of the samples in this cell
    pushq %r15                  # r15 = sy
    subq  $8, %rsp              # keep the stack 16-byte aligned for mvaddch

    movq $0, %r12               # row = 0
.row_loop:
    cmpq $ROWS, %r12
    jge  .rows_done

    movq $0, %r13               # col = 0
.col_loop:
    cmpq $COLS, %r13
    jge  .next_row

    movq $0, %r14               # sum = 0
    movq $0, cell_owner         # no slugcat seen in this cell yet

    movq $0, %r15               # sy = 0
.sy_loop:
    cmpq $SUB_Y, %r15
    jge  .samples_done

    movq $0, %rbx               # sx = 0
.sx_loop:
    cmpq $SUB_X, %rbx
    jge  .next_sy

    # x = col * CELL_W + sx * SAMPLE_STEP + SAMPLE_OFF
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

    call sample_point           # rax = brightness at (x, y)
    addq %rax, %r14             # sum += brightness

    incq %rbx
    jmp  .sx_loop
.next_sy:
    incq %r15
    jmp  .sy_loop

.samples_done:
    # index = (sum + 4) / 8   -> average of the 8 samples, rounded
    addq $4, %r14
    shrq $3, %r14               # divide by 8

    # nothing here? let the sky shader fill the cell (see sky.s)
    cmpq $0, %r14
    jne  .have_index
    movq %r13, %rdi             # sky_shade(col, row)
    movq %r12, %rsi
    call sky_shade
    movq %rax, %r14             # 0, 1 or 2
    movq $SKY_PAIR, cell_owner  # dim cloud colour
.have_index:

    movzbq ramp(%r14), %rdx     # rdx = ramp[index]  (the character)
    movq cell_owner, %rax
    shlq $8, %rax               # COLOR_PAIR(n) is just n << 8
    orq  %rax, %rdx             # character + colour

    movq %r12, %rdi             # mvaddch(row, col, ch)
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

    #-----------------------------------------------------------------------------
    # long sample_point(long x /* %rdi */, long y /* %rsi */) -> %rax
    #
    # How bright is the world at point (x, y)? Returns 0..9.
    #   b = 0
    #   for each platform j: if (x, y) is inside it: b = TERRAIN_SHADE
    #   for each platform j except the floor:          (wet film on top)
    #       if x0 <= x < x1 and y0 - plat_wet[j] / 8 <= y < y0 and b < WATER_SHADE:
    #           b = WATER_SHADE;  cell_owner = WATER_PAIR (unless a slugcat has it)
    #   if y >= FLOOR_TOP - water_level and b < WATER_SHADE:
    #       b = WATER_SHADE;  cell_owner = WATER_PAIR (unless a slugcat has it)
    #   for each chunk i:
    #       d2 = (x - cx)^2 + (y - cy)^2       (squared distance, no sqrt!)
    #       r2 = r * r
    #       if d2 < r2:                        (inside the circle)
    #           shade = 9 if d2 * 4 < r2       (d < r/2:     centre)
    #                   8 if d2 * 2 < r2       (d < 0.71 r:  middle)
    #                   6 otherwise            (near the outline)
    #           if shade > b: b = shade;  cell_owner = i / 2 + 1
    #   return b
    #-----------------------------------------------------------------------------
sample_point:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq $0, %rax               # rax = brightness so far

    #-----------------------------------------------------------------------------
    # platforms
    #-----------------------------------------------------------------------------
    movq $0, %rcx               # rcx = platform index
.sp_plat_loop:
    cmpq $NUM_PLATS, %rcx
    jge  .sp_plats_done

    cmpq plat_x0(,%rcx,8), %rdi # x < x0 -> outside
    jl   .sp_next_plat
    cmpq plat_x1(,%rcx,8), %rdi # x >= x1 -> outside
    jge  .sp_next_plat
    cmpq plat_y0(,%rcx,8), %rsi # y < y0 -> outside
    jl   .sp_next_plat
    cmpq plat_y1(,%rcx,8), %rsi # y >= y1 -> outside
    jge  .sp_next_plat
    movq $TERRAIN_SHADE, %rax   # inside this platform

.sp_next_plat:
    incq %rcx
    jmp  .sp_plat_loop
.sp_plats_done:

    #-----------------------------------------------------------------------------
    # wet platforms: a thin water film on top, plat_wet / 8 subunits tall
    #-----------------------------------------------------------------------------
    movq $1, %rcx               # start at 1: the floor gets the lake instead
.sp_film_loop:
    cmpq $NUM_PLATS, %rcx
    jge  .sp_films_done

    cmpq plat_x0(,%rcx,8), %rdi # x outside the platform -> skip
    jl   .sp_next_film
    cmpq plat_x1(,%rcx,8), %rdi
    jge  .sp_next_film
    cmpq plat_y0(,%rcx,8), %rsi # y at or below the top -> not the film
    jge  .sp_next_film
    movq plat_wet(,%rcx,8), %r8
    shrq $3, %r8                # r8 = film height = plat_wet / 8
    movq plat_y0(,%rcx,8), %r9
    subq %r8, %r9               # r9 = top of the film
    cmpq %r9, %rsi              # y above the film -> skip
    jl   .sp_next_film

    cmpq $WATER_SHADE, %rax     # inside the film: water
    jge  .sp_next_film
    movq $WATER_SHADE, %rax
    cmpq $0, cell_owner
    jne  .sp_next_film
    movq $WATER_PAIR, cell_owner

.sp_next_film:
    incq %rcx
    jmp  .sp_film_loop
.sp_films_done:

    #-----------------------------------------------------------------------------
    # water: below the surface (and not inside a platform)
    #-----------------------------------------------------------------------------
    movq $FLOOR_TOP, %r8
    subq water_level, %r8       # r8 = water surface
    cmpq %r8, %rsi
    jl   .sp_dry                # above the water
    cmpq $WATER_SHADE, %rax
    jge  .sp_dry                # a platform is brighter: keep it
    movq $WATER_SHADE, %rax
    cmpq $0, cell_owner         # don't paint a slugcat cell blue
    jne  .sp_dry
    movq $WATER_PAIR, cell_owner
.sp_dry:

    #-----------------------------------------------------------------------------
    # body chunks (circles)
    #-----------------------------------------------------------------------------
    movq $0, %rcx               # rcx = chunk index
.sp_chunk_loop:
    cmpq $NUM_CHUNKS, %rcx
    jge  .sp_done

    movq %rdi, %r8
    subq chunk_x(,%rcx,8), %r8  # r8 = dx = x - cx
    imulq %r8, %r8              # r8 = dx * dx
    movq %rsi, %r9
    subq chunk_y(,%rcx,8), %r9  # r9 = dy = y - cy
    imulq %r9, %r9              # r9 = dy * dy
    addq %r9, %r8               # r8 = d2

    movq chunk_r(,%rcx,8), %r10
    imulq %r10, %r10            # r10 = r2

    cmpq %r10, %r8              # d2 >= r2 -> outside the circle
    jge  .sp_next_chunk

    movq $6, %r11               # r11 = shade: near the outline
    movq %r8, %r9
    shlq $1, %r9                # r9 = d2 * 2
    cmpq %r10, %r9
    jge  .sp_have_shade
    movq $8, %r11               # middle
    shlq $1, %r9                # r9 = d2 * 4
    cmpq %r10, %r9
    jge  .sp_have_shade
    movq $9, %r11               # centre
.sp_have_shade:

    cmpq %rax, %r11             # not brighter than what we have -> skip
    jle  .sp_next_chunk
    movq %r11, %rax             # b = shade
    movq %rcx, %r9
    shrq $1, %r9                # player = chunk / 2
    incq %r9                    # colour pair = player + 1
    movq %r9, cell_owner

.sp_next_chunk:
    incq %rcx
    jmp  .sp_chunk_loop

.sp_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret
