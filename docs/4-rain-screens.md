# 4. Rain/flood + main loop + screens (`rain.s`, `main.s`, `screens/*`)

Your job is to explain the flood (the game's timer), the main loop that ties everything together, and the menus.

## Part A: rain and the flood (`rain.s`)

### The rule (from our original scope)
> When rain touches the ground it disappears in a second. But as the game goes on there's more and more rain, and rain that lands on other rain doesn't disappear, so it builds up and eventually drowns you.

How we implemented it:
- A drop that hits **dry floor** leaves a **splash** in that column (`splash[col] = 30` frames, about 1 s), and then it's gone.
- A drop that lands on a splash that's still there, or on water (`water_total > 0`), **stays**: `water_total += 8`.
- Early on there's so little rain that a second drop almost never hits a splash within its 1 s. As the rain gets heavier, that becomes likely, the first water appears, and from then on every drop adds water. Nobody "starts" the flood; it emerges from the rule.

### Heavier and heavier: `rain_level`
`rain_level` is a chance out of 1000. Every frame we try `RAIN_TRIES` (16) times: `if rand() % 1000 < rain_level: spawn_drop()`. So the drops per frame ≈ 16 · rain_level / 1000.

Every second: `rain_level += rain_level / 32 + 1`. Because it grows by a **fraction of itself** (about 3%), it grows exponentially: a drizzle at first (8 → ~0.13 drops per frame), pouring after ~2 minutes (1000 → 16 per frame). Exponential growth felt right because it starts calm and then suddenly gets scary.

### A flat lake
The floor is one connected basin, so water is always flat: `water_level = water_total / COLS`. The surface is at `FLOOR_TOP - water_level`. (Our first version kept water per column and let it flow to neighbours, but with integer division a small slope never evened out (`diff / 4` is 0 for diff < 4), so we got a V-shaped lake. One shared level is simpler *and* correct.)

### Platforms
A drop that hits a platform (`find_platform`):
- makes the platform wetter: `plat_wet[j] += 4` (max 128). Every frame it drains by 1, so in light rain it stays dry and in heavy rain it's soaked. The sampler draws a water film `plat_wet / 8` subunits tall on top (render.s).
- **drips off the nearer edge**: its x moves to just left of `x0` or just right of `x1`, and it keeps falling. So all the rain still ends up in the lake, and you see little streams at the platform edges.

### `update_rain` in order
1. ramp `rain_level` every 30 frames
2. spawn new drops
3. move drops: lake/floor check first (splash or water), then platforms (wet + drip)
4. splashes and wet platforms dry by 1
5. `water_level = water_total / COLS`

`spawn_drop` looks for a free slot (`drop_active == 0`) among 1024. If all are busy, the drop is skipped. 1024 is enough: 16 drops/frame × ~48 frames to fall = ~770.

### `check_drowning`
A head below the surface (`head.y > FLOOR_TOP - water_level`) means drowned. One drowned → the other wins (`kills++`); both in the same frame → draw (`winner = -1`). It's skipped if a spear already ended the round this frame.

### `draw_rain`
Drops are a blue `'` at `(y >> 5, x >> 4)`, splashes a blue `.` on the row above the floor. The lake itself is drawn by the sampler, not here.

## Part B: the main loop (`main.s`)

Setup, in order, and why:
1. `setlocale(LC_ALL, "C.UTF-8")` comes **before** `initscr`. Without it ncursesw prints the title's UTF-8 block characters as garbage.
2. `initscr`, `noecho` (don't print typed keys), `cbreak` (keys come immediately, without Enter), `keypad` (arrow keys become one code), `curs_set(0)` (hide the cursor), `timeout(0)` (`getch` doesn't wait), `set_escdelay(25)`.
3. `start_color` + 4 `init_pair`s.
4. `srand(time(0))`, `reset_round`.

The loop: `poll_input` → `erase` → size check (`getmaxy/getmaxx` < 36/120 → message) → dispatch on `game_state` → `refresh` → `usleep(33000)`.
- **Why `timeout(0)` + `usleep` and not `timeout(33)`?** With `timeout(33)`, `getch` returns *as soon as a key is pressed*, so the game would speed up while you type. Now every frame takes the same time.
- **Why `erase` + `refresh` every frame without flicker?** ncurses keeps a copy of the screen and `refresh` only sends the cells that changed.
- The END scene doesn't call `update_physics`, so the world freezes behind the text.

## Part C: screens (`screens/`)

- `text.s`: `draw_lines(table, count, row, col)` calls `mvaddstr` for each string in a table of addresses (`.quad str0, str1, ...`), moving `rbx` 8 bytes per entry.
- `home.s`: the README title (UTF-8 blocks, 91 wide, so centred at col 14) in P1's colour via `attron/attroff(COLOR_PAIR(1))`, plus the menu text.
- `guide.s`, `credits.s`: the same pattern, a figlet title plus text.
- `end.s`: `draw_world` + rain + spears (frozen), then "P%ld WINS!" (or "DRAW") and the score with `mvprintw`.
- `fights.s`: the in-game draw order plus the score.
- Scene switching is all in `inputs.s` (Enter / g / c), and `main.s` only dispatches.

## Likely questions
- *How long does a round last if nobody throws?* About 2–2.5 minutes, until the water reaches the high platforms.
- *Why per mille and not percent?* With percent, the lowest non-zero chance × 16 tries would already be too much rain at the start. Per mille lets it start very gently.
- *Why is the lake level `total / COLS`?* The same amount of water spread over 120 columns, a flat surface. It's one division per frame.
- *What does `-lncursesw -ltinfo` mean?* ncursesw is ncurses with wide/UTF-8 support, and tinfo is the terminal database library that ncurses needs.

## Try it yourself
1. Make the rain start at 0 and only start after 20 seconds.
2. Make the lake rise twice as fast (one constant).
3. Add a "rain %" next to the score (hint: `rain_level / 10`, like the old HUD in git history).
4. Make water slow the slugcats down (in `physics.s`: if a chunk is under the surface, halve `vx`).
