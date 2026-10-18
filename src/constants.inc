# constants.inc - shared .equ values, .include'd by the files that use them
#
# positions/speeds are in subunits: a cell is 16 wide and 32 tall
# (cells are ~2x taller than wide). so the 120x36 world is 1920x1152, y goes down.
# this way things can move less than a cell per frame without floats.

# ---- screen -----------------------------------------------------------------
.equ COLS,        120           # terminal width  (cells)
.equ ROWS,        36            # terminal height (cells)
.equ CELL_W,      16            # one cell is 16 subunits wide
.equ CELL_H,      32            # ... and 32 subunits tall
.equ WORLD_W,     1920          # COLS * CELL_W
.equ FRAME_US,    33000         # 33 ms per frame -> ~30 FPS (for usleep)

# ---- brightness sampler -------------------------------------------------------
# every cell is tested at 2 x 4 = 8 points, SAMPLE_STEP apart, starting
# SAMPLE_OFF from the cell's corner
.equ SUB_X,       2
.equ SUB_Y,       4
.equ SAMPLE_STEP, 8             # CELL_W / SUB_X  (= CELL_H / SUB_Y)
.equ SAMPLE_OFF,  4             # SAMPLE_STEP / 2  -> sample the middle
.equ TERRAIN_SHADE, 4           # brightness of platforms (0..9)

# ---- players / body chunks ----------------------------------------------------
# a slugcat is 2 circles ("chunks"), index = player * 2 + part (0 head, 1 body)
.equ NUM_PLAYERS, 2
.equ NUM_CHUNKS,  4
.equ NUM_PLATS,   6

# ---- physics (subunits per frame) ------------------------------------------
.equ RUN_SPEED,   32            # top running speed       (2 cells/frame)
.equ RUN_ACCEL,   2             # reach it fast: close 1/2 of the gap per frame
.equ FRICTION_MUL, 3            # when not running: vx = vx * 3 / 4
.equ FRICTION_DIV, 4
.equ GRAVITY,     5             # added to vy every frame (~0.31)
.equ MAX_FALL,    56            # terminal velocity       (~3.5)
.equ JUMP_HEAD,   64            # head gets a bigger kick (~4.0) than...
.equ JUMP_BODY,   50            # ...the body (~3.1): the jump stretches
.equ KEY_HOLD,    12            # frames one key press keeps you running

# ---- spine (spring between head and body) ----------------------------------
.equ REST_LEN,    64            # relaxed head-body distance (4 cells)
.equ SPINE_DIV,   4             # fix 1/4 of the stretch per frame (springy)

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
.equ WET_PER_DROP,  4           # a drop hitting a platform makes it wetter...
.equ WET_MAX,       128         # ...up to this; it drains 1 per frame
                                # water film on top = plat_wet / 8 (max 16)
.equ WATER_SHADE,   3           # brightness of water (0..9)
.equ WATER_PAIR,    3           # colour pair of water (blue)

# ---- scenes -----------------------------------------------------------------
.equ SCENE_HOME,    0
.equ SCENE_GAME,    1
.equ SCENE_END,     2
.equ SCENE_GUIDE,   3
.equ SCENE_CREDITS, 4

# ---- colours (xterm 256-colour palette numbers) -----------------------------
.equ P1_COLOR,    150           # #afd787 green  (closest to 195, 232, 141)
.equ P2_COLOR,    209           # #ff875f orange (closest to 255, 150, 108)

# ---- sky shader (sky.s) ------------------------------------------------------
.equ SKY_BIAS_ROW, 8            # rows above this get extra clouds
.equ SKY_THIN,     14           # v above this: thin cloud '.'
.equ SKY_THICK,    20           # v above this: thick cloud ':'
.equ SKY_PAIR,     4            # colour pair of the clouds
.equ SKY_COLOR,    60           # #5f5f87 slate blue-grey

# ---- misc -------------------------------------------------------------------
.equ LC_ALL,      6             # from <locale.h> (glibc)

# ---- key codes (from <ncurses.h>) -----------------------------------------
.equ KEY_ESC,     27
.equ KEY_NEWLINE, 10            # Enter (ncurses turns \r into \n)
.equ KEY_DOWN,    258
.equ KEY_UP,      259
.equ KEY_LEFT,    260
.equ KEY_RIGHT,   261
