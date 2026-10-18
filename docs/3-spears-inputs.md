# 3. Spears + inputs (`spears.s`, `inputs.s`)

Your job is to explain how a key press becomes an action, and how a spear goes from lying on a platform to ending the round.

## Part A: inputs (`inputs.s`)

### The problem: terminals have no "key released"
A terminal only sends "this key was typed". When you hold a key, it sends the key again and again (auto-repeat), after a short delay. There is no "released" event. So we can't know directly that a key is held.

**Our solution:** a move key sets `move_timer[p] = KEY_HOLD` (12 frames). The slugcat keeps running while `move_timer > 0`, and `update_physics` counts it down. While you hold the key, auto-repeat keeps refilling it; when you let go, it runs out after ~0.4 s and you stop. `s` / ↓ sets it to 0 for an instant stop.

**Jump quirk:** if you hold `d` and tap `w`, the terminal stops repeating `d` (it only repeats the most recent key). So a jump while running also refills `move_timer`, otherwise you'd stop mid-jump.

**Known limitation:** when both players hold keys at the same time, only the last key repeats, so one of them stutters. Every terminal game has this; a real game would read the keyboard directly.

### `poll_input`
```
loop:
    key = getch()            timeout(0) in main.s -> returns -1 right away if nothing
    if key == -1: done       (so ALL keys pressed since last frame are handled)
    x / Esc -> quit_flag = 1
    Enter   -> depends on the scene (start round / next round / back to menu)
    g, c    -> guide / credits, only from the menu
    P1 keys -> rcx = 0,  P2 keys -> rcx = 1
    then shared code: move_dir(,%rcx,8), move_timer(,%rcx,8), jump_req, grab_req
```
- The key goes in `%rbx`, which is callee-saved, because `getch` is called again in the loop. One push is an odd count, so `subq $8, %rsp` for alignment.
- `movl %eax, %ebx`: `getch` returns an `int`, and writing a 32-bit register zeroes the top half.
- **Same code for both players**: the P1 and P2 branches only differ in the value put into `%rcx`, then both jump to the same `.move_left` etc. That's why the per-player data is in arrays.
- `keypad(stdscr, 1)` in `main.s` makes arrow keys arrive as single codes (`KEY_LEFT` = 260) instead of 3-byte escape sequences. `set_escdelay(25)` makes Esc arrive fast (ncurses normally waits 1 s to see if Esc is the start of an arrow key).
- Inputs only set **requests** (`jump_req`, `grab_req`). The physics decides whether they happen: a jump only works if `on_ground`, a grab only if a spear is close. That keeps input and game rules separate.

## Part B: spears (`spears.s`)

### State machine
```
           grab (close enough)           throw
 STUCK  ───────────────────────►  HELD ─────────►  FLYING
   ▲                                                 │
   └──────────────── lands in a platform ────────────┘
                                                     │ hits the other slugcat
                                                     ▼
                                               round over (SCENE_END)
```
Each spear has `spear_state`, `spear_owner` (who holds it / who threw it), `spear_dir` (where the tip points) and x/y/vx/vy.

### `spawn_spears`
For each spear: a random platform `rand() % NUM_PLATS`, then a random x on it `x0 + 16 + rand() % (width - 32)` (keeping away from the edges), with y = the platform top, state STUCK.
- `movl %eax, %eax` clears the top of rax after `rand`, `movq $0, %rdx`, then `divq`: the remainder in `%rdx` is the `% n`.
- `srand(time(0))` in `main.s` gives different spears every run.

### `grab_or_throw(p)`
- **Holding one** (`held_spear[p] >= 0`) → throw: state FLYING, `vx = move_dir * SPEAR_SPEED` (56), `vy = -SPEAR_LIFT` (−8, slightly up), `held_spear = -1`.
- **Empty hands** → look for a STUCK spear with `|spear.x - body.x| < 48` and `|spear.y - body.y| < 96`. Abs value: `cmpq $0; jge; negq`. The first one that's close enough gets picked up.

We measure from the **body**, because the body is at the feet, which is where a spear stuck in the ground is.

### `update_spears`
- **HELD**: copies the owner's head x/y and `move_dir`, so it's carried at the head and points the way you face.
- **FLYING**:
  1. `vy += 1` (lighter gravity than slugcats, so a flatter arc), capped at 24.
  2. `x += vx`, `y += vy`.
  3. Hits a screen edge → `vx = 0` and it just drops.
  4. Falling into a platform (`find_platform` from render.s) → stick: `y = plat_y0`, state STUCK. Like slugcats, it passes through platforms while going up.
  5. Hit test against every chunk of the **other** player (`chunk / 2 != owner`): `d² < r²` → `winner = owner`, `kills[owner]++`, `game_state = SCENE_END`.
- `SPEAR_MAX_FALL` (24) is below the platform thickness (32), so a spear can't jump through a platform in a single frame.

### `draw_spears`
These are plain characters drawn on top of the world: `row = y >> 5`, `col = x >> 4`.
- STUCK: `|` on the 3 rows above the platform.
- HELD/FLYING: `-----` from col−2 to col+2, with the tip `>` or `<` depending on `spear_dir`.
`mvaddch` ignores positions outside the window, so no bounds checks are needed.

## Likely questions
- *Why does the round end immediately on a hit?* `game_state = SCENE_END`, and then `main.s` stops calling `update_physics`, so the frame freezes with the spear in the body. That's the end screen.
- *Can you hit yourself?* No, chunks of the owner are skipped.
- *Why is the throw direction `move_dir` and not the velocity?* So that you can throw while standing still, the way you last faced.
- *What if both players grab the same spear in the same frame?* The player loop handles P1 first, and the spear is no longer STUCK when P2 checks.

## Try it yourself
1. Add a 7th spear (one constant, nothing else, and explain why that's enough).
2. Make spears fly straight (no gravity) and see what changes in gameplay.
3. Add a key that drops the held spear (back to STUCK at your feet).
4. Make `s` also work as "throw".
