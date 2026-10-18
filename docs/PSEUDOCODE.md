# painworld — Pseudocode Design

This document describes the intended behavior of every module before implementation.
Review this, suggest changes, then I will fill in the assembly.

---

## Global Constants

```text
SCREEN_W      = 80     # terminal width in cells
SCREEN_H      = 24     # terminal height in cells
FRAME_MS      = 33     # ~30 FPS, passed to timeout()
PLAYER_H_R    = 2      # head radius (cells)
PLAYER_B_R    = 1      # bottom radius (cells)
GRAVITY       = 0.25   # pixels/frame^2  (stored as fixed-point * 64)
JUMP_VEL      = -3.0   # pixels/frame    (fixed-point * 64)
WALK_SPEED    = 1.0    # pixels/frame    (fixed-point * 64)
SPEAR_SPEED   = 2.0    # pixels/frame    (fixed-point * 64)
RAIN_SPAWN_CH = 5      # per-frame chance (out of 100) a new rain drop appears
RAIN_SPEED    = 1      # cells/frame downward
```

All physics use 16.16 fixed-point (integer part << 16) for sub-cell precision.

---

## Data Layout (src/data.s)

```
player:                          # slugcat state (one for now, two later)
  player_x       dq 40           # head center X (fixed-point)
  player_y       dq 12           # head center Y (fixed-point)
  player_vx      dq 0            # horizontal velocity
  player_vy      dq 0            # vertical velocity
  player_dir     dq 1            # 1 = right, -1 = left (head tilt)
  player_state   dq IDLE         # IDLE=0, WALK=1, JUMP=2, LIE_DOWN=3, CLIMB=4, DEAD=5
  player_on_rope dq 0            # 1 if colliding with a rope
  player_on_ground dq 0          # 1 if standing on platform

spear:                           # equipped / thrown spear
  spear_x        dq 0
  spear_y        dq 0
  spear_vx       dq 0
  spear_active   dq 0            # 0 = not flying, 1 = in flight
  spear_equipped dq 0            # 1 = player holding it

rain_drop:                       # array of MAX_RAIN drops
  rain_x         dq 0            # repeated MAX_RAIN times
  rain_y         dq 0
  rain_active    dq 0
MAX_RAIN     = 50

platform:                        # static platform segments
  plat_x1        dq 0
  plat_x2        dq 0
  plat_y         dq 0

rope:                            # rope segments
  rope_x         dq 0
  rope_y1        dq 0
  rope_y2        dq 0

game_state   dq SCENE_HOME       # SCENE_HOME=0, SCENE_GAME=1, SCENE_END=2, ...
kill_count   dq 0
```

---

## Input Handling (src/inputs.s)

```text
function poll_input():
    key = getch()                      # ncurses, returns -1 on timeout
    if key == -1: return               # no key this frame

    # Map keys to actions
    if key == 'a' or key == LEFT:   player_dir = -1; player_state = WALK
    if key == 'd' or key == RIGHT:  player_dir = 1;  player_state = WALK
    if key == 'w' or key == UP:     if player_on_rope: player_state = CLIMB
                                    else:              player_state = JUMP
    if key == 's' or key == DOWN:   player_state = LIE_DOWN
    if key == '.':                  if !spear_active: spear_equipped = 1
                                    else:              throw_spear()
    if key == 'q':                  game_state = SCENE_END

    # Release keys reset to IDLE (simplified: key-up not detected in ncurses,
    # so we rely on frame-based state machine)
```

Calling convention comment example for `getch`:
```
# getch() -> %rax
call getch
```

---

## Physics (src/data.s / src/fights.s)

### Movement (per frame)

```
# Integrate velocity
player_x += player_vx
player_y += player_vy

# Apply gravity when not on ground / rope
if !player_on_ground && !player_on_rope:
    player_vy += GRAVITY

# Clamp to screen bounds
player_x = clamp(player_x, PLAYER_H_R, SCREEN_W - PLAYER_H_R)
player_y = clamp(player_y, PLAYER_B_R, SCREEN_H - PLAYER_B_R)

# Ground collision
if player_y + PLAYER_B_R >= ground_y_at(player_x):
    player_y = ground_y_at(player_x) - PLAYER_B_R
    player_vy = 0
    player_on_ground = 1
else:
    player_on_ground = 0

# Rope collision (simple vertical line check)
if |player_x - rope_x| < 1 && player_y in [rope_y1, rope_y2]:
    player_on_rope = 1
else:
    player_on_rope = 0

# Lying down: reduce hitbox height
if player_state == LIE_DOWN:
    effective_bottom_radius = PLAYER_B_R  # full dodge height
else:
    effective_bottom_radius = PLAYER_B_R
```

### Jump

```
# Only from ground
if player_on_ground && key == UP:
    player_vy = JUMP_VEL
    player_on_ground = 0
    player_state = JUMP
```

### Climb

```
if player_on_rope && key == UP:
    player_y -= WALK_SPEED
if player_on_rope && key == DOWN:
    player_y += WALK_SPEED
if player_on_rope && (key == LEFT or key == RIGHT):
    # Jump off rope: treat current pos as ground
    player_vy = JUMP_VEL
    player_on_rope = 0
    player_state = JUMP
```

### Spear

```
# Equip: when '.' pressed over a spear on ground
if key == '.' && !spear_active && spear_on_ground_nearby:
    spear_equipped = 1

# Throw: when '.' pressed while equipped
if key == '.' && spear_equipped:
    spear_x = player_x + (player_dir * 2)          # spawn in front of head
    spear_y = player_y - (PLAYER_H_R * 0.75)       # 75% of head height
    spear_vx = player_dir * SPEAR_SPEED
    spear_vy = 0
    spear_active = 1
    spear_equipped = 0

# Spear flight (semi-parabola, always horizontal while flying)
spear_x += spear_vx
spear_y += spear_vy
spear_vy += GRAVITY * 0.5                          # lighter gravity for spear

# When spear hits ground/platform:
if spear_y + radius >= ground_y_at(spear_x):
    spear_y = ground_y_at(spear_x) - radius
    spear_active = 0
    spear_vx = 0
    spear_vy = 0
    spear becomes vertical (visual only)

# Collision with player:
if |spear_x - player_x| < (PLAYER_H_R + spear_radius) &&
   |spear_y - player_y| < (PLAYER_B_R + spear_radius):
    player_state = DEAD
    game_state = SCENE_END
```

### Rain

```
# Spawn
each frame:
    if random(0, 99) < RAIN_SPAWN_CH:
        find inactive rain drop
        rain_x = random(0, SCREEN_W)
        rain_y = 0
        rain_active = 1

# Update
for each active rain drop:
    rain_y += RAIN_SPEED
    if rain_y >= SCREEN_H:
        rain_active = 0                          # disappears on ground
    # Rain-on-rain does NOT disappear (accumulation/drought mechanic)
```

---

## Rendering Pipeline

```
frame():
    erase()                                      # clear ncurses buffer

    # Layer -2: Sky (static, e.g. '.' chars)
    # Layer -1: Background (static ASCII art)
    # Layer  0: Ground + Slugcats
    # Layer  1: Foreground + Rain + Spears
    # Layer  2: UI & Stats (top-left corner)

    draw_player()        # head circle 'O', bottom circle 'o', tilt by dir
    draw_spears()
    draw_rain()
    draw_ui()            # show keys pressed, kill count, FPS

    refresh()            # push to terminal
```

---

## Scenes

```
SCENE_HOME:
    draw ASCII title
    draw [Start] [Guide] [Credits]
    on 'Enter' -> SCENE_GAME

SCENE_GAME:
    run physics + rendering loop above
    on player death -> SCENE_END

SCENE_END:
    draw "GAME OVER"
    draw kill count
    on any key -> SCENE_HOME

SCENE_GUIDE / SCENE_CREDITS:
    static text screens
```

---

## File Responsibilities

| File | Contents |
|------|----------|
| `src/main.s` | Entry point, ncurses init, main game loop, scene dispatcher |
| `src/data.s` | All `.data` / `.bss` variables (players, spears, rain, platforms, ropes) |
| `src/inputs.s` | `poll_input()` — reads getch, updates player_state / flags |
| `src/rain.s` | `spawn_rain()`, `update_rain()`, `draw_rain()` |
| `src/screens/home.s` | `draw_home()` |
| `src/screens/fights.s` | `draw_game()`, `update_physics()`, `draw_player()`, `draw_spears()` |
