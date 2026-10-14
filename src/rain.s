# =============================================================================
# slugcat.s  --  terminal "Rain World"-style prototype, x86-64, AT&T syntax
#
# Hand-written port of slugcat.c. Every function below has a twin with the
# same name in the C file; read them side by side.
#
# Build:  gcc -nostdlib -static -g -o slugcat slugcat.s
# Keys:   a/d = run, w or space = jump, s = stop, q = quit
#
# NO C LIBRARY is used: we talk to Linux directly with the `syscall`
# instruction. That is why the entry point is _start and not main.
#
# CHEAT SHEET
# -----------
# AT&T operand order is  SOURCE, DESTINATION:   addss %xmm1, %xmm0  -> xmm0 += xmm1
#
# Floats live in the xmm registers. The "ss" instructions work on one 32-bit
# float:  movss (copy)  addss subss mulss divss  sqrtss  minss maxss
#         comiss a, b   compares b with a and sets flags like an UNSIGNED
#                       integer compare, so afterwards use  ja/jae/jb/jbe
#         cvtsi2ss      int   -> float
#         cvttss2si     float -> int (truncates)
#         xorps %x,%x   sets a register to 0.0
#
# Linux syscall convention: number in rax, arguments in rdi, rsi, rdx.
# The kernel destroys rcx and r11; everything else survives.
#
# Function convention (the normal System V one):
#   float arguments in xmm0, xmm1; pointer/int arguments in rdi, rsi
#   float result in xmm0
#   rbx, rbp, r12-r15 must be preserved by a function (push/pop them)
#   ALL xmm registers may be destroyed by a call
# =============================================================================

# ---------- constants (same names as the #defines in the C file) ----------
        .equ    COLS, 80
        .equ    ROWS, 24
        .equ    SUB_X, 2                # samples per cell, horizontally
        .equ    SUB_Y, 4                # samples per cell, vertically
        .equ    KEY_HOLD_FRAMES, 12

        # Chunk layout:  struct { float x, y, vx, vy, r; }
        .equ    C_X, 0
        .equ    C_Y, 4
        .equ    C_VX, 8
        .equ    C_VY, 12
        .equ    C_R, 16
        .equ    CHUNK_SIZE, 20
        .equ    NUM_CHUNKS, 2

        # Rect layout:   struct { float x0, y0, x1, y1; }
        .equ    R_X0, 0
        .equ    R_Y0, 4
        .equ    R_X1, 8
        .equ    R_Y1, 12
        .equ    RECT_SIZE, 16
        .equ    NUM_RECTS, 2

        # Linux syscall numbers
        .equ    SYS_read, 0
        .equ    SYS_write, 1
        .equ    SYS_ioctl, 16
        .equ    SYS_nanosleep, 35
        .equ    SYS_exit, 60

        # Terminal settings (struct termios as the kernel sees it)
        .equ    TCGETS, 0x5401          # ioctl: read settings
        .equ    TCSETS, 0x5402          # ioctl: write settings
        .equ    TERMIOS_SIZE, 60
        .equ    T_LFLAG, 12             # offset of c_lflag
        .equ    T_VTIME, 22             # offset of c_cc[VTIME]
        .equ    T_VMIN, 23              # offset of c_cc[VMIN]
        .equ    ICANON, 2               # line buffering
        .equ    ECHO, 8                 # print typed keys
        .equ    ISIG, 1                 # Ctrl-C kills the program

# =============================================================================
# Read-only data
# =============================================================================
        .section .rodata

# Tuning knobs -- play with these!
run_speed:      .float 1.2              # target head speed, units/frame
run_accel:      .float 0.25             # how fast the head reaches it
friction:       .float 0.85             # vx multiplier when not driven
gravity:        .float 0.18
max_fall:       .float 2.5
jump_head:      .float -2.6             # negative = up (y points down)
jump_body:      .float -2.0             # smaller kick -> stretchy jump
rest_len:       .float 5.0              # relaxed head-body distance
spine_k:        .float 0.2              # spine stiffness
terrain_bright: .float 0.45
shade_base:     .float 0.55             # slugcat brightness at its outline
shade_range:    .float 0.45             # extra brightness towards its centre
ground_ny:      .float -0.7             # normal.y below this = standing
world_w:        .float 80.0

# Plain numbers
tiny:           .float 0.000001
quarter:        .float 0.25
half:           .float 0.5
one:            .float 1.0
ramp_scale:     .float 1.125            # 9/8: sum of 8 samples -> index 0..9

# Terrain: left, top, right, bottom
rects:          .float 0.0, 44.0, 80.0, 48.0    # floor
                .float 50.0, 36.0, 62.0, 44.0   # box

ramp:           .ascii " .:-=+*#%@"     # dark -> bright, 10 characters

hud:            .ascii " a/d run   w/space jump   s stop   q quit "
        .equ    HUD_LEN, . - hud        # "." = current address, so this is the length

init_seq:       .ascii "\033[2J\033[?25l"         # clear screen, hide cursor
        .equ    INIT_LEN, . - init_seq
exit_seq:       .ascii "\033[?25h\033[24;1H\n"    # show cursor, go to bottom
        .equ    EXIT_LEN, . - exit_seq

frame_time:     .quad 0, 33333333       # struct timespec: 0 s + 33.3 ms (~30 fps)

# =============================================================================
# Variables with a starting value
# =============================================================================
        .data
chunks:
head:           .float 22.0, 30.0, 0.0, 0.0, 2.2        # x, y, vx, vy, r
body:           .float 17.0, 30.0, 0.0, 0.0, 2.8

move_dir:       .long 0                 # -1 = left, +1 = right
move_timer:     .long 0                 # frames of running left
jump_req:       .long 0                 # 1 if jump was pressed this frame
on_ground:      .long 0                 # 1 if a chunk stood on something
quit:           .long 0

# =============================================================================
# Zero-initialised buffers
# =============================================================================
        .bss
term_orig:      .skip 64                # terminal settings to restore on exit
term_raw:       .skip 64                # our modified copy
keybuf:         .skip 32                # keys typed since the last frame
framebuf:       .skip 4096              # one whole frame of text

# =============================================================================
# Code
# =============================================================================
        .text
        .globl  _start

# -----------------------------------------------------------------------------
# _start: program entry point  (C: main)
# -----------------------------------------------------------------------------
_start:
        call    term_setup
.Lmain_loop:
        call    read_input
        cmpl    $0, quit(%rip)
        jne     .Lmain_exit
        call    update_physics
        call    render

        mov     $SYS_nanosleep, %eax    # nanosleep(&frame_time, NULL)
        lea     frame_time(%rip), %rdi
        xor     %esi, %esi
        syscall
        jmp     .Lmain_loop

.Lmain_exit:
        call    term_restore
        mov     $SYS_exit, %eax         # exit(0)
        xor     %edi, %edi
        syscall

# -----------------------------------------------------------------------------
# term_setup: no line buffering, no echo, read() never waits
# -----------------------------------------------------------------------------
term_setup:
        mov     $SYS_ioctl, %eax        # ioctl(0, TCGETS, &term_orig)
        xor     %edi, %edi
        mov     $TCGETS, %esi
        lea     term_orig(%rip), %rdx
        syscall

        lea     term_orig(%rip), %rsi   # term_raw = term_orig
        lea     term_raw(%rip), %rdi
        mov     $TERMIOS_SIZE, %ecx
        rep movsb                       # copy rcx bytes from (rsi) to (rdi)

        andl    $~(ICANON | ECHO | ISIG), term_raw + T_LFLAG(%rip)
        movb    $0, term_raw + T_VTIME(%rip)
        movb    $0, term_raw + T_VMIN(%rip)     # read() returns at once

        mov     $SYS_ioctl, %eax        # ioctl(0, TCSETS, &term_raw)
        xor     %edi, %edi
        mov     $TCSETS, %esi
        lea     term_raw(%rip), %rdx
        syscall

        mov     $SYS_write, %eax        # write(1, init_seq, INIT_LEN)
        mov     $1, %edi
        lea     init_seq(%rip), %rsi
        mov     $INIT_LEN, %edx
        syscall
        ret

# -----------------------------------------------------------------------------
# term_restore: put the terminal back the way we found it
# -----------------------------------------------------------------------------
term_restore:
        mov     $SYS_ioctl, %eax        # ioctl(0, TCSETS, &term_orig)
        xor     %edi, %edi
        mov     $TCSETS, %esi
        lea     term_orig(%rip), %rdx
        syscall

        mov     $SYS_write, %eax        # write(1, exit_seq, EXIT_LEN)
        mov     $1, %edi
        lea     exit_seq(%rip), %rsi
        mov     $EXIT_LEN, %edx
        syscall
        ret

# -----------------------------------------------------------------------------
# read_input: read every key typed since last frame and update the
#             move_dir / move_timer / jump_req / quit variables
# -----------------------------------------------------------------------------
read_input:
        mov     $SYS_read, %eax         # n = read(0, keybuf, 32)
        xor     %edi, %edi
        lea     keybuf(%rip), %rsi
        mov     $32, %edx
        syscall
        test    %rax, %rax
        jle     .Lri_done               # 0 = nothing typed, <0 = error

        mov     %rax, %rcx              # rcx = keys left to look at
        lea     keybuf(%rip), %rsi      # rsi = pointer to the current key
.Lri_loop:
        movzbl  (%rsi), %eax            # al = key

        cmp     $'q', %al
        je      .Lri_quit
        cmp     $3, %al                 # 3 = Ctrl-C
        je      .Lri_quit
        cmp     $'a', %al
        je      .Lri_left
        cmp     $'d', %al
        je      .Lri_right
        cmp     $'s', %al
        je      .Lri_stop
        cmp     $'w', %al
        je      .Lri_jump
        cmp     $' ', %al
        je      .Lri_jump
        jmp     .Lri_next               # some other key: ignore

.Lri_quit:
        movl    $1, quit(%rip)
        jmp     .Lri_next
.Lri_left:
        movl    $-1, move_dir(%rip)
        movl    $KEY_HOLD_FRAMES, move_timer(%rip)
        jmp     .Lri_next
.Lri_right:
        movl    $1, move_dir(%rip)
        movl    $KEY_HOLD_FRAMES, move_timer(%rip)
        jmp     .Lri_next
.Lri_stop:
        movl    $0, move_timer(%rip)
        jmp     .Lri_next
.Lri_jump:
        movl    $1, jump_req(%rip)
        # Holding d and tapping w makes the terminal stop repeating d,
        # so a jump during a run refills the run timer.
        cmpl    $0, move_timer(%rip)
        jle     .Lri_next
        movl    $KEY_HOLD_FRAMES, move_timer(%rip)

.Lri_next:
        inc     %rsi
        dec     %rcx
        jnz     .Lri_loop
.Lri_done:
        ret

# -----------------------------------------------------------------------------
# collide_chunk: push a circle out of a rectangle if they overlap
#   rdi = pointer to Chunk,  rsi = pointer to Rect
# -----------------------------------------------------------------------------
collide_chunk:
        movss   C_X(%rdi), %xmm0        # xmm0 = c.x
        movss   C_Y(%rdi), %xmm1        # xmm1 = c.y

        # Closest point of the rect = circle centre clamped into the rect
        movaps  %xmm0, %xmm2
        maxss   R_X0(%rsi), %xmm2
        minss   R_X1(%rsi), %xmm2       # xmm2 = closest x
        movaps  %xmm1, %xmm3
        maxss   R_Y0(%rsi), %xmm3
        minss   R_Y1(%rsi), %xmm3       # xmm3 = closest y

        subss   %xmm2, %xmm0            # xmm0 = dx
        subss   %xmm3, %xmm1            # xmm1 = dy

        movaps  %xmm0, %xmm2
        mulss   %xmm2, %xmm2
        movaps  %xmm1, %xmm3
        mulss   %xmm3, %xmm3
        addss   %xmm3, %xmm2            # xmm2 = d2 = dx*dx + dy*dy

        movss   C_R(%rdi), %xmm4        # xmm4 = r
        movaps  %xmm4, %xmm5
        mulss   %xmm5, %xmm5            # xmm5 = r*r
        comiss  %xmm5, %xmm2
        jae     .Lcc_done               # d2 >= r*r : not touching

        comiss  tiny(%rip), %xmm2
        ja      .Lcc_push               # d2 > tiny : the normal case

        # Centre is INSIDE the rect: emergency exit, pop on top of it
        movss   R_Y0(%rsi), %xmm0
        subss   %xmm4, %xmm0
        movss   %xmm0, C_Y(%rdi)        # c.y = rect.top - r
        movl    $0, C_VY(%rdi)          # c.vy = 0.0 (all-zero bits = 0.0f)
        movl    $1, on_ground(%rip)
        ret

.Lcc_push:
        sqrtss  %xmm2, %xmm2            # xmm2 = d
        divss   %xmm2, %xmm0            # xmm0 = nx   (unit normal, rect -> circle)
        divss   %xmm2, %xmm1            # xmm1 = ny
        subss   %xmm2, %xmm4            # xmm4 = pen = r - d

        movaps  %xmm0, %xmm5            # c.x += nx * pen
        mulss   %xmm4, %xmm5
        addss   C_X(%rdi), %xmm5
        movss   %xmm5, C_X(%rdi)
        movaps  %xmm1, %xmm5            # c.y += ny * pen
        mulss   %xmm4, %xmm5
        addss   C_Y(%rdi), %xmm5
        movss   %xmm5, C_Y(%rdi)

        # vn = velocity along the normal; negative = moving into the surface
        movss   C_VX(%rdi), %xmm2
        mulss   %xmm0, %xmm2
        movss   C_VY(%rdi), %xmm3
        mulss   %xmm1, %xmm3
        addss   %xmm3, %xmm2            # xmm2 = vn
        xorps   %xmm3, %xmm3
        comiss  %xmm3, %xmm2
        jae     .Lcc_ground             # vn >= 0 : already moving away

        movaps  %xmm0, %xmm3            # c.vx -= nx * vn
        mulss   %xmm2, %xmm3
        movss   C_VX(%rdi), %xmm5
        subss   %xmm3, %xmm5
        movss   %xmm5, C_VX(%rdi)
        movaps  %xmm1, %xmm3            # c.vy -= ny * vn
        mulss   %xmm2, %xmm3
        movss   C_VY(%rdi), %xmm5
        subss   %xmm3, %xmm5
        movss   %xmm5, C_VY(%rdi)

.Lcc_ground:
        comiss  ground_ny(%rip), %xmm1
        jae     .Lcc_done               # ny >= -0.7 : wall or ceiling
        movl    $1, on_ground(%rip)     # normal points up: we are standing
.Lcc_done:
        ret

# -----------------------------------------------------------------------------
# update_physics: one frame of movement
# -----------------------------------------------------------------------------
update_physics:
        push    %rbx                    # rbx = pointer to current chunk
        push    %r12                    # r12 = chunks left
        push    %r13                    # r13 = pointer to current rect
        push    %r14                    # r14 = rects left

        # ---- 1. Running: only the HEAD is driven, the body gets dragged ----
        movl    move_timer(%rip), %eax
        test    %eax, %eax
        jle     .Lup_coast
        dec     %eax
        movl    %eax, move_timer(%rip)
        cvtsi2ssl move_dir(%rip), %xmm0
        mulss   run_speed(%rip), %xmm0  # xmm0 = target speed
        movss   head + C_VX(%rip), %xmm1
        subss   %xmm1, %xmm0            # target - vx
        mulss   run_accel(%rip), %xmm0
        addss   %xmm0, %xmm1            # vx += (target - vx) * accel
        movss   %xmm1, head + C_VX(%rip)
        jmp     .Lup_body_friction
.Lup_coast:
        movss   head + C_VX(%rip), %xmm1
        mulss   friction(%rip), %xmm1
        movss   %xmm1, head + C_VX(%rip)
.Lup_body_friction:
        movss   body + C_VX(%rip), %xmm1
        mulss   friction(%rip), %xmm1
        movss   %xmm1, body + C_VX(%rip)

        # ---- 2. Jump: head launches faster than the body -> stretch ----
        cmpl    $0, jump_req(%rip)
        je      .Lup_no_jump
        cmpl    $0, on_ground(%rip)
        je      .Lup_no_jump
        movss   jump_head(%rip), %xmm0
        movss   %xmm0, head + C_VY(%rip)
        movss   jump_body(%rip), %xmm0
        movss   %xmm0, body + C_VY(%rip)
.Lup_no_jump:
        movl    $0, jump_req(%rip)

        # ---- 3. Gravity and movement, for each chunk ----
        lea     chunks(%rip), %rbx
        mov     $NUM_CHUNKS, %r12d
.Lup_move:
        movss   C_VY(%rbx), %xmm0
        addss   gravity(%rip), %xmm0
        minss   max_fall(%rip), %xmm0   # vy = min(vy + gravity, max_fall)
        movss   %xmm0, C_VY(%rbx)
        addss   C_Y(%rbx), %xmm0        # y += vy
        movss   %xmm0, C_Y(%rbx)
        movss   C_X(%rbx), %xmm0        # x += vx
        addss   C_VX(%rbx), %xmm0
        movss   %xmm0, C_X(%rbx)
        add     $CHUNK_SIZE, %rbx
        dec     %r12d
        jnz     .Lup_move

        # ---- 4. Spine: pull head and body towards rest_len apart ----
        movss   head + C_X(%rip), %xmm0
        subss   body + C_X(%rip), %xmm0 # xmm0 = dx
        movss   head + C_Y(%rip), %xmm1
        subss   body + C_Y(%rip), %xmm1 # xmm1 = dy
        movaps  %xmm0, %xmm2
        mulss   %xmm2, %xmm2
        movaps  %xmm1, %xmm3
        mulss   %xmm3, %xmm3
        addss   %xmm3, %xmm2
        sqrtss  %xmm2, %xmm2            # xmm2 = d = current distance
        comiss  tiny(%rip), %xmm2
        jbe     .Lup_spine_done         # on top of each other: no direction

        movaps  %xmm2, %xmm3
        subss   rest_len(%rip), %xmm3
        divss   %xmm2, %xmm3
        mulss   spine_k(%rip), %xmm3    # xmm3 = k = (d - rest)/d * stiffness
        mulss   %xmm3, %xmm0            # xmm0 = cx = dx * k
        mulss   %xmm3, %xmm1            # xmm1 = cy = dy * k

        # The head moves by -c, the body by +c (positions AND velocities)
        movss   head + C_X(%rip), %xmm4
        subss   %xmm0, %xmm4
        movss   %xmm4, head + C_X(%rip)
        movss   head + C_VX(%rip), %xmm4
        subss   %xmm0, %xmm4
        movss   %xmm4, head + C_VX(%rip)
        movss   head + C_Y(%rip), %xmm4
        subss   %xmm1, %xmm4
        movss   %xmm4, head + C_Y(%rip)
        movss   head + C_VY(%rip), %xmm4
        subss   %xmm1, %xmm4
        movss   %xmm4, head + C_VY(%rip)

        movss   body + C_X(%rip), %xmm4
        addss   %xmm0, %xmm4
        movss   %xmm4, body + C_X(%rip)
        movss   body + C_VX(%rip), %xmm4
        addss   %xmm0, %xmm4
        movss   %xmm4, body + C_VX(%rip)
        movss   body + C_Y(%rip), %xmm4
        addss   %xmm1, %xmm4
        movss   %xmm4, body + C_Y(%rip)
        movss   body + C_VY(%rip), %xmm4
        addss   %xmm1, %xmm4
        movss   %xmm4, body + C_VY(%rip)
.Lup_spine_done:

        # ---- 5. Collisions: every chunk against every rect ----
        movl    $0, on_ground(%rip)
        lea     chunks(%rip), %rbx
        mov     $NUM_CHUNKS, %r12d
.Lup_chunk:
        lea     rects(%rip), %r13
        mov     $NUM_RECTS, %r14d
.Lup_rect:
        mov     %rbx, %rdi
        mov     %r13, %rsi
        call    collide_chunk
        add     $RECT_SIZE, %r13
        dec     %r14d
        jnz     .Lup_rect

        # Screen edges: keep x between r and world_w - r
        movss   C_X(%rbx), %xmm0
        maxss   C_R(%rbx), %xmm0
        movss   world_w(%rip), %xmm1
        subss   C_R(%rbx), %xmm1
        minss   %xmm1, %xmm0
        movss   %xmm0, C_X(%rbx)

        add     $CHUNK_SIZE, %rbx
        dec     %r12d
        jnz     .Lup_chunk

        pop     %r14
        pop     %r13
        pop     %r12
        pop     %rbx
        ret

# -----------------------------------------------------------------------------
# sample_scene: how bright is the vector world at one point?
#   xmm0 = x, xmm1 = y        returns brightness 0..1 in xmm0
#   (uses xmm2-xmm9, rax, rcx; calls nothing)
# -----------------------------------------------------------------------------
sample_scene:
        xorps   %xmm2, %xmm2            # xmm2 = b = 0.0  (the answer so far)

        # ---- Terrain: flat brightness inside any rectangle ----
        lea     rects(%rip), %rax
        mov     $NUM_RECTS, %ecx
.Lss_rect:
        comiss  R_X0(%rax), %xmm0
        jb      .Lss_next_rect          # x <  left
        comiss  R_X1(%rax), %xmm0
        jae     .Lss_next_rect          # x >= right
        comiss  R_Y0(%rax), %xmm1
        jb      .Lss_next_rect          # y <  top
        comiss  R_Y1(%rax), %xmm1
        jae     .Lss_next_rect          # y >= bottom
        movss   terrain_bright(%rip), %xmm2
.Lss_next_rect:
        add     $RECT_SIZE, %rax
        dec     %ecx
        jnz     .Lss_rect

        # ---- Slugcat: closest point on the head->body segment ----
        movss   head + C_X(%rip), %xmm3 # xmm3 = ax
        movss   head + C_Y(%rip), %xmm4 # xmm4 = ay
        movss   body + C_X(%rip), %xmm5
        subss   %xmm3, %xmm5            # xmm5 = dx = body.x - head.x
        movss   body + C_Y(%rip), %xmm6
        subss   %xmm4, %xmm6            # xmm6 = dy

        movaps  %xmm5, %xmm7
        mulss   %xmm7, %xmm7
        movaps  %xmm6, %xmm8
        mulss   %xmm8, %xmm8
        addss   %xmm8, %xmm7            # xmm7 = len2 = segment length squared

        xorps   %xmm8, %xmm8            # xmm8 = t = 0  (0 = head, 1 = body)
        comiss  tiny(%rip), %xmm7
        jbe     .Lss_have_t             # zero-length segment: keep t = 0

        movaps  %xmm0, %xmm8
        subss   %xmm3, %xmm8
        mulss   %xmm5, %xmm8            # (x - ax) * dx
        movaps  %xmm1, %xmm9
        subss   %xmm4, %xmm9
        mulss   %xmm6, %xmm9            # (y - ay) * dy
        addss   %xmm9, %xmm8
        divss   %xmm7, %xmm8            # t = dot / len2
        xorps   %xmm9, %xmm9
        maxss   %xmm9, %xmm8            # t = max(t, 0)
        minss   one(%rip), %xmm8        # t = min(t, 1)
.Lss_have_t:

        mulss   %xmm8, %xmm5
        addss   %xmm3, %xmm5
        subss   %xmm0, %xmm5            # xmm5 = px = ax + dx*t - x
        mulss   %xmm8, %xmm6
        addss   %xmm4, %xmm6
        subss   %xmm1, %xmm6            # xmm6 = py = ay + dy*t - y
        mulss   %xmm5, %xmm5
        mulss   %xmm6, %xmm6
        addss   %xmm6, %xmm5
        sqrtss  %xmm5, %xmm5            # xmm5 = d = distance to the spine

        # Allowed distance blends from head radius to body radius
        movss   head + C_R(%rip), %xmm3
        movss   body + C_R(%rip), %xmm4
        subss   %xmm3, %xmm4
        mulss   %xmm8, %xmm4
        addss   %xmm4, %xmm3            # xmm3 = r = hr + (br - hr) * t

        comiss  %xmm3, %xmm5
        jae     .Lss_done               # d >= r : outside the slugcat

        # Shading: bright near the spine, dimmer at the outline
        divss   %xmm3, %xmm5            # d / r
        movss   one(%rip), %xmm4
        subss   %xmm5, %xmm4            # 1 - d/r
        mulss   shade_range(%rip), %xmm4
        addss   shade_base(%rip), %xmm4 # xmm4 = s
        maxss   %xmm4, %xmm2            # b = max(b, s)

.Lss_done:
        movaps  %xmm2, %xmm0            # return b
        ret

# -----------------------------------------------------------------------------
# render: vector world -> brightness per cell -> ASCII -> terminal
#   rbx = write pointer into framebuf
#   r12 = row,  r13 = col,  r14 = sy,  r15 = sx  (sample indices in the cell)
#   (%rsp) = sum of the samples of the current cell (a float on the stack)
# -----------------------------------------------------------------------------
render:
        push    %rbx
        push    %r12
        push    %r13
        push    %r14
        push    %r15
        sub     $16, %rsp               # room for the local float `sum`

        lea     framebuf(%rip), %rbx
        movb    $0x1b, (%rbx)           # ESC [ H  = cursor to top-left
        movb    $'[', 1(%rbx)
        movb    $'H', 2(%rbx)
        add     $3, %rbx

        xor     %r12d, %r12d            # row = 0
.Lr_row:
        xor     %r13d, %r13d            # col = 0
.Lr_col:
        movl    $0, (%rsp)              # sum = 0.0
        xor     %r14d, %r14d            # sy = 0
.Lr_sy:
        xor     %r15d, %r15d            # sx = 0
.Lr_sx:
        # x = sx*0.5 + 0.25 + col
        cvtsi2ss %r15d, %xmm0
        mulss   half(%rip), %xmm0
        addss   quarter(%rip), %xmm0
        cvtsi2ss %r13d, %xmm2
        addss   %xmm2, %xmm0
        # y = sy*0.5 + 0.25 + row*2      (a cell is 2 units tall)
        cvtsi2ss %r14d, %xmm1
        mulss   half(%rip), %xmm1
        addss   quarter(%rip), %xmm1
        lea     (%r12, %r12), %eax      # eax = row * 2
        cvtsi2ss %eax, %xmm2
        addss   %xmm2, %xmm1

        call    sample_scene            # xmm0 = brightness at (x, y)
        addss   (%rsp), %xmm0
        movss   %xmm0, (%rsp)           # sum += brightness

        inc     %r15d
        cmp     $SUB_X, %r15d
        jl      .Lr_sx
        inc     %r14d
        cmp     $SUB_Y, %r14d
        jl      .Lr_sy

        # Brightness meter -> character: index = (int)(sum * 9/8 + 0.5)
        movss   (%rsp), %xmm0
        mulss   ramp_scale(%rip), %xmm0
        addss   half(%rip), %xmm0
        cvttss2si %xmm0, %eax           # eax = 0..9
        lea     ramp(%rip), %rcx
        movzbl  (%rcx, %rax), %eax      # al = ramp[index]
        movb    %al, (%rbx)
        inc     %rbx

        inc     %r13d
        cmp     $COLS, %r13d
        jl      .Lr_col

        inc     %r12d
        cmp     $ROWS, %r12d
        jge     .Lr_rows_done           # no newline after the last row
        movb    $'\n', (%rbx)           # (it would scroll the terminal)
        inc     %rbx
        jmp     .Lr_row
.Lr_rows_done:

        # Help text over the start of the top row (after the 3-byte ESC[H)
        lea     hud(%rip), %rsi
        lea     framebuf + 3(%rip), %rdi
        mov     $HUD_LEN, %ecx
        rep movsb

        # One write() for the whole frame = no flicker
        mov     $SYS_write, %eax
        mov     $1, %edi
        lea     framebuf(%rip), %rsi
        mov     %rbx, %rdx
        sub     %rsi, %rdx              # length = write pointer - start
        syscall

        add     $16, %rsp
        pop     %r15
        pop     %r14
        pop     %r13
        pop     %r12
        pop     %rbx
        ret

