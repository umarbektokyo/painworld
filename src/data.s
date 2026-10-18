    #=============================================================================
    # painworld — src/data.s
    # All game-state variables live here. Single source of truth for the sim.
    # Every value is in subunits (see constants.inc): 16 subunits = 1 cell wide.
    #
    # Arrays are read with an index register, 8 bytes per entry:
    #     movq chunk_x(,%rcx,8), %rax      # rax = chunk_x[rcx]
    #=============================================================================

    .include "constants.inc"

    .data

    .globl chunk_x, chunk_y, chunk_vx, chunk_vy, chunk_r, jump_kick
    .globl start_x, start_y, start_dir
    .globl move_dir, move_timer, jump_req, grab_req, on_ground, held_spear
    .globl spear_x, spear_y, spear_vx, spear_vy, spear_state, spear_owner
    .globl spear_dir
    .globl drop_x, drop_y, drop_active, water_total, water_level, splash
    .globl rain_level, rain_clock, drowned
    .globl plat_x0, plat_y0, plat_x1, plat_y1
    .globl game_state, quit_flag, last_key, kills, winner
    .globl cell_owner, ramp

    #-----------------------------------------------------------------------------
    # Body chunks (circles). Index = player * 2 + part (0 = head, 1 = body).
    #                  P1 head  P1 body  P2 head  P2 body
    #-----------------------------------------------------------------------------
chunk_x:    .quad     0,       0,       0,       0   # centre x
chunk_y:    .quad     0,       0,       0,       0   # centre y
chunk_vx:   .quad     0,       0,       0,       0   # velocity x
chunk_vy:   .quad     0,       0,       0,       0   # velocity y
chunk_r:    .quad    42,      35,      42,      35   # radius (head is bigger)

    # Where each round starts (copied into chunk_x / chunk_y by reset_round)
start_x:    .quad   240,     160,    1040,    1120
start_y:    .quad   160,     160,     160,     160   # high up, they fall in

    # Jump kick per part. Index = part (0 = head, 1 = body).
jump_kick:  .quad JUMP_HEAD, JUMP_BODY

    #-----------------------------------------------------------------------------
    # Per-player state. Index = player (0 = P1, 1 = P2).
    #-----------------------------------------------------------------------------
start_dir:  .quad 1, -1        # P1 faces right, P2 faces left
move_dir:   .quad 1, -1        # -1 = left, 1 = right (also where you throw)
move_timer: .quad 0, 0         # frames left to keep running (refilled by keys)
jump_req:   .quad 0, 0         # 1 = jump was pressed this frame
grab_req:   .quad 0, 0         # 1 = grab/throw was pressed this frame
on_ground:  .quad 0, 0         # 1 = a chunk is standing on a platform
held_spear: .quad -1, -1       # index of the spear you carry, -1 = none
kills:      .quad 0, 0         # rounds won (kept between rounds)

    #-----------------------------------------------------------------------------
    # Spears. Index = spear. spear_state is SPEAR_STUCK / HELD / FLYING.
    #-----------------------------------------------------------------------------
spear_x:     .skip NUM_SPEARS * 8
spear_y:     .skip NUM_SPEARS * 8
spear_vx:    .skip NUM_SPEARS * 8
spear_vy:    .skip NUM_SPEARS * 8
spear_state: .skip NUM_SPEARS * 8
spear_owner: .skip NUM_SPEARS * 8   # player holding / who threw it
spear_dir:   .skip NUM_SPEARS * 8   # -1 / 1: which way the tip points

    #-----------------------------------------------------------------------------
    # Rain + flood
    #-----------------------------------------------------------------------------
drop_x:      .skip MAX_DROPS * 8
drop_y:      .skip MAX_DROPS * 8
drop_active: .skip MAX_DROPS * 8    # 1 = this drop is falling
water_total: .quad 0                # all the water that stayed, added up
water_level: .quad 0                # water_total / COLS: height above the floor
splash:      .skip COLS * 8         # frames left of a splash, per column
rain_level:  .quad RAIN_START       # spawn chance (%), grows over time
rain_clock:  .quad 0                # frames since rain_level last grew
drowned:     .quad 0, 0             # per player: 1 = head is under water

    #-----------------------------------------------------------------------------
    # Platforms: rectangles from (x0, y0) top-left to (x1, y1) bottom-right.
    # You can jump up through them and land on their top edge.
    #                floor  left   right  middle
    #-----------------------------------------------------------------------------
plat_x0:    .quad     0,   128,   832,   480
plat_y0:    .quad   704,   512,   512,   320
plat_x1:    .quad  1280,   448,  1152,   800
plat_y1:    .quad   768,   544,   544,   352

    #-----------------------------------------------------------------------------
    # Game flow
    #-----------------------------------------------------------------------------
game_state: .quad SCENE_GAME   # start straight in the game for now
quit_flag:  .quad 0            # 1 = leave the main loop
last_key:   .quad 0            # last key code read (shown in the HUD)
winner:     .quad 0            # player who won the last round, -1 = draw

    #-----------------------------------------------------------------------------
    # Rendering
    #-----------------------------------------------------------------------------
cell_owner: .quad 0            # colour pair of the slugcat in the current cell
ramp:       .ascii " .:-=+*#%@" # brightness 0..9, dark -> bright
