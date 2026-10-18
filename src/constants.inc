#=============================================================================
# painworld — src/constants.inc
# Shared constants. Every .s file that needs them does:
#     .include "constants.inc"
#
# UNITS
#   All positions and speeds are stored in "subunits": 16 subunits = 1 world
#   unit = the width of one text cell. A text cell is about twice as tall as it
#   is wide, so one cell is 16 subunits wide and 32 subunits tall.
#   The world is 120 cells x 36 cells = 1920 x 1152 subunits. y points DOWN.
#
#   Working in subunits lets things move by less than one cell per frame
#   without floats: speed 4 = a quarter of a cell per frame.
#=============================================================================

# ---- screen -----------------------------------------------------------------
.equ COLS,        120           # terminal width  (cells)
.equ ROWS,        36            # terminal height (cells)
.equ CELL_W,      16            # one cell is 16 subunits wide
.equ CELL_H,      32            # ... and 32 subunits tall
.equ WORLD_W,     1920          # COLS * CELL_W
.equ FRAME_US,    33000         # 33 ms per frame -> ~30 FPS (for usleep)

# ---- brightness sampler -------------------------------------------------------
# Each cell is tested at SUB_X * SUB_Y = 8 points (2 across, 4 down).
# Points are SAMPLE_STEP apart and start SAMPLE_OFF from the cell's corner.
.equ SUB_X,       2
.equ SUB_Y,       4
.equ SAMPLE_STEP, 8             # CELL_W / SUB_X  (= CELL_H / SUB_Y)
.equ SAMPLE_OFF,  4             # SAMPLE_STEP / 2  -> sample the middle
.equ TERRAIN_SHADE, 4           # brightness of platforms (0..9)

# ---- players / body chunks ----------------------------------------------------
# Each slugcat is 2 circles ("chunks"): head and body.
# Chunk index = player * 2 + part   (part 0 = head, 1 = body)
.equ NUM_PLAYERS, 2
.equ NUM_CHUNKS,  4
.equ NUM_PLATS,   6

# ---- physics (subunits per frame) ------------------------------------------
.equ RUN_SPEED,   19            # top running speed       (~1.2 cells/frame)
.equ GRAVITY,     3             # added to vy every frame (~0.19)
.equ MAX_FALL,    40            # terminal velocity       (~2.5)
.equ JUMP_HEAD,   42            # head gets a bigger kick (~2.6) than...
.equ JUMP_BODY,   32            # ...the body (~2.0): the jump stretches
.equ KEY_HOLD,    12            # frames one key press keeps you running

# ---- spine (spring between head and body) ----------------------------------
.equ REST_LEN,    64            # relaxed head-body distance (4 cells)
.equ SPINE_DIV,   5             # fix 1/5 of the stretch per frame (springy)

# ---- spears -----------------------------------------------------------------
.equ NUM_SPEARS,    6
.equ SPEAR_STUCK,   0           # stuck in a platform, can be picked up
.equ SPEAR_HELD,    1           # carried by spear_owner
.equ SPEAR_FLYING,  2           # thrown by spear_owner
.equ SPEAR_SPEED,   56          # horizontal speed when thrown (~3.5)
.equ SPEAR_LIFT,    8           # small upward kick when thrown
.equ SPEAR_GRAVITY, 1           # spears fall slower than slugcats
.equ SPEAR_MAX_FALL, 24         # < platform thickness, so it can't skip one
.equ GRAB_RANGE_X,  48          # how close the body must be to grab (3 cells)
.equ GRAB_RANGE_Y,  96

# ---- rain + flood -------------------------------------------------------------
.equ MAX_DROPS,     1024        # raindrops falling at the same time
.equ RAIN_SPEED,    24          # how far a drop falls per frame (~0.75 row)
.equ RAIN_TRIES,    16          # spawn attempts per frame, each succeeding
                                # rain_level out of 1000 times (per mille)
.equ RAIN_START,    8           # ~0.13 drops per frame: a light drizzle
.equ RAIN_MAX,      1000        # 16 drops per frame: pouring
.equ RAIN_RAMP_FRAMES, 30       # every second:
.equ RAIN_GROWTH,   32          #   rain_level += rain_level / 32 + 1  (~3%)
.equ SPLASH_FRAMES, 30          # a drop on dry floor stays 1 second
.equ DROP_WATER,    8           # water one drop adds to water_total
.equ FLOOR_TOP,     1088        # top of the floor (plat_y0[0])
.equ SPLASH_ROW,    33          # the text row just above the floor
.equ WATER_SHADE,   3           # brightness of water (0..9)
.equ WATER_PAIR,    3           # colour pair of water (blue)

# ---- scenes -----------------------------------------------------------------
.equ SCENE_HOME,    0
.equ SCENE_GAME,    1
.equ SCENE_END,     2
.equ SCENE_GUIDE,   3
.equ SCENE_CREDITS, 4

# ---- misc -------------------------------------------------------------------
.equ LC_ALL,      6             # from <locale.h> (glibc)

# ---- key codes (from <ncurses.h>) -----------------------------------------
.equ KEY_ESC,     27
.equ KEY_NEWLINE, 10
.equ KEY_RETURN,  13
.equ KEY_ENTER,   343           # Enter on the number pad
.equ KEY_DOWN,    258
.equ KEY_UP,      259
.equ KEY_LEFT,    260
.equ KEY_RIGHT,   261
