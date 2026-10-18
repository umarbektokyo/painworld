#=============================================================================
# painworld — src/constants.inc
# Shared constants. Every .s file that needs them does:
#     .include "constants.inc"
#
# UNITS
#   All positions and speeds are stored in "subunits": 16 subunits = 1 world
#   unit = the width of one text cell. A text cell is about twice as tall as it
#   is wide, so one cell is 16 subunits wide and 32 subunits tall.
#   The world is 80 cells x 24 cells = 1280 x 768 subunits. y points DOWN.
#
#   Working in subunits lets things move by less than one cell per frame
#   without floats: speed 4 = a quarter of a cell per frame.
#=============================================================================

# ---- screen -----------------------------------------------------------------
.equ COLS,        80            # terminal width  (cells)
.equ ROWS,        24            # terminal height (cells)
.equ CELL_W,      16            # one cell is 16 subunits wide
.equ CELL_H,      32            # ... and 32 subunits tall
.equ WORLD_W,     1280          # COLS * CELL_W
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
.equ NUM_PLATS,   4

# ---- physics (subunits per frame) ------------------------------------------
.equ RUN_SPEED,   19            # top running speed       (~1.2 cells/frame)
.equ GRAVITY,     3             # added to vy every frame (~0.19)
.equ MAX_FALL,    40            # terminal velocity       (~2.5)
.equ JUMP_SPEED,  40            # vy right after a jump   (~2.5)
.equ KEY_HOLD,    12            # frames one key press keeps you running

# ---- scenes -----------------------------------------------------------------
.equ SCENE_HOME,    0
.equ SCENE_GAME,    1
.equ SCENE_END,     2
.equ SCENE_GUIDE,   3
.equ SCENE_CREDITS, 4

# ---- key codes (from <ncurses.h>) -----------------------------------------
.equ KEY_ESC,     27
.equ KEY_DOWN,    258
.equ KEY_UP,      259
.equ KEY_LEFT,    260
.equ KEY_RIGHT,   261
