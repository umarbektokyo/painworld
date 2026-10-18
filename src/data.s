# every array entry is 8 bytes, read like: movq chunk_x(,%rcx,8), %rax

    .include "constants.inc"

    .data

    .globl chunk_x, chunk_y, chunk_vx, chunk_vy, chunk_r, jump_kick
    .globl start_x, start_y, start_dir
    .globl move_dir, move_timer, jump_req, grab_req, on_ground, held_spear
    .globl spear_x, spear_y, spear_vx, spear_vy, spear_state, spear_owner
    .globl spear_dir
    .globl drop_x, drop_y, drop_active, water_total, water_level, splash, plat_wet
    .globl rain_level, rain_clock, drowned
    .globl plat_x0, plat_y0, plat_x1, plat_y1
    .globl game_state, quit_flag, frame_count, kills, winner
    .globl cell_owner, ramp

# body chunks (circles), index = player * 2 + part (0 head, 1 body)
#                P1 head  P1 body  P2 head  P2 body
chunk_x:    .quad     0,       0,       0,       0
chunk_y:    .quad     0,       0,       0,       0
chunk_vx:   .quad     0,       0,       0,       0
chunk_vy:   .quad     0,       0,       0,       0
chunk_r:    .quad    42,      35,      42,      35   # head is a bit bigger

start_x:    .quad   400,     320,    1520,    1600   # copied in by reset_round
start_y:    .quad   160,     160,     160,     160

jump_kick:  .quad JUMP_HEAD, JUMP_BODY               # index = part

# per player (0 = P1, 1 = P2)
start_dir:  .quad 1, -1         # P1 faces right, P2 left
move_dir:   .quad 1, -1         # -1 left, 1 right (also the throw direction)
move_timer: .quad 0, 0          # frames left to keep running
jump_req:   .quad 0, 0          # jump pressed this frame
grab_req:   .quad 0, 0          # spear key pressed this frame
on_ground:  .quad 0, 0          # standing on something
held_spear: .quad -1, -1        # spear index we carry, -1 = none
kills:      .quad 0, 0          # score, kept between rounds

# spears, state = SPEAR_STUCK / HELD / FLYING
spear_x:     .skip NUM_SPEARS * 8
spear_y:     .skip NUM_SPEARS * 8
spear_vx:    .skip NUM_SPEARS * 8
spear_vy:    .skip NUM_SPEARS * 8
spear_state: .skip NUM_SPEARS * 8
spear_owner: .skip NUM_SPEARS * 8   # who holds it / who threw it
spear_dir:   .skip NUM_SPEARS * 8   # -1 / 1, where the tip points

# rain + flood
drop_x:      .skip MAX_DROPS * 8
drop_y:      .skip MAX_DROPS * 8
drop_active: .skip MAX_DROPS * 8
water_total: .quad 0                # all the water that stayed
water_level: .quad 0                # water_total / COLS, height above the floor
splash:      .skip COLS * 8         # frames left of a splash, per column
plat_wet:    .skip NUM_PLATS * 8    # how wet each platform top is
rain_level:  .quad RAIN_START       # spawn chance out of 1000, goes up
rain_clock:  .quad 0                # frames since rain_level last went up
drowned:     .quad 0, 0             # per player

# platforms: rectangles (x0, y0) to (x1, y1)
#              floor  low-L  low-R  middle high-L high-R
plat_x0:    .quad     0,   160,  1312,   720,   288,  1280
plat_y0:    .quad  1088,   896,   896,   704,   512,   512
plat_x1:    .quad  1920,   608,  1760,  1200,   640,  1632
plat_y1:    .quad  1152,   928,   928,   736,   544,   544

game_state:  .quad SCENE_HOME
quit_flag:   .quad 0
frame_count: .quad 0            # +1 every frame, the sky uses it as time
winner:      .quad 0            # -1 = draw

cell_owner:  .quad 0            # colour pair for the cell being drawn
ramp:        .ascii " ::-=+*#%@" # brightness 0..9, needs exactly 10 chars
# ramp:        .ascii " 123456789" # brightness 0..9
