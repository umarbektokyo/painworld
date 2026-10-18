# 1. Rendering + sky (`render.s`, `sky.s`, `screens/fights.s`)

Your job is to explain how numbers in `data.s` turn into the picture. It's the most "graphics" part of the project, and it's the part the professor liked in the demo.

## The idea: a brightness sampler

We never draw a slugcat as a fixed set of characters. Instead, for **every one of the 120×36 cells**, we ask the world "how bright are you here?" at 8 points inside the cell (2 across, 4 down), average the answers, and pick a character from a dark-to-bright ramp:

```
ramp: " .:-=+*#%@"      index 0 = empty ... 9 = brightest
```

A cell that a circle only half covers gets about half the brightness, so a dimmer character. That's why the edges look soft and the shapes slide smoothly instead of jumping cell by cell. It's basically anti-aliasing, done with text.

```
cell = 16 x 32 subunits, samples at +4 and +12 across, +4 +12 +20 +28 down:
   . .
   . .        8 samples, each 8 subunits apart, offset 4 from the corner
   . .        (SAMPLE_STEP = 8, SAMPLE_OFF = 4)
   . .
```

## `draw_world` (render.s)

Four nested loops: `row` (r12), `col` (r13), `sy` (r15), `sx` (rbx). They're all in callee-saved registers because `sample_point` and `mvaddch` are called inside the loops and would destroy caller-saved ones. Five pushes is an odd number, so we add `subq $8, %rsp` to keep the stack 16-aligned for `mvaddch`.

For each sample point:
```
x = col*16 + sx*8 + 4
y = row*32 + sy*8 + 4
sum += sample_point(x, y)
```
After 8 samples: `index = (sum + 4) >> 3`, which is the average rounded to the nearest (adding half the divisor before dividing rounds instead of truncating). If `index == 0` the cell is empty, and we ask the sky shader instead.

The character is `ramp[index]` (`movzbq ramp(%r14), %rdx` loads one byte and zero-extends it). Colour: `cell_owner` is a colour pair number set by `sample_point`, and `ch | (pair << 8)` makes it coloured, because in ncurses `COLOR_PAIR(n)` is `n << 8`.

## `sample_point(x, y)` → brightness 0..9

The brightest thing at that point wins (the current best is kept in `%r10`):

| what | test | brightness | colour |
|---|---|---|---|
| platform | `find_platform(x,y) >= 0` | 4 (`TERRAIN_SHADE`) | default |
| wet film on a platform | `y0 - plat_wet/8 <= y < y0` | 3 (`WATER_SHADE`) | blue |
| lake | `y >= FLOOR_TOP - water_level` | 3 | blue |
| slugcat circle | `dx² + dy² < r²` | 6 edge / 8 middle / 9 centre | P1/P2 |

**No square roots.** "Inside the circle" is `d² < r²`. For the shading, `d < r/2 ⇔ 4d² < r²` and `d < 0.71r ⇔ 2d² < r²`, so `shlq $1` (×2) twice gives us both tests. Brighter towards the centre makes the slugcat look round.

Water only paints a cell blue if no slugcat has claimed it yet (`cmpq $0, cell_owner`), so a slugcat standing in water keeps its colour.

## `find_platform(x, y)` → platform index or −1

This is a plain loop over the 6 rectangles: `x0 <= x < x1 && y0 <= y < y1`. Three files use it (here, spears sticking, rain hitting platforms), so it's one shared function. It only touches `%rax` and `%rcx`, which is why callers can keep using `%rdi/%rsi` (x, y) after calling it. That's a promise we can make because we wrote the function; for a C function you couldn't assume it.

## The sky shader (`sky.s`)

`sky_shade(col, row)` is called for empty cells. Like a GPU fragment shader, it only gets its position and the time (`frame_count`), and returns 0, 1 or 2 (empty, `.`, `:`).

```
v  = sine[(col + t/8) & 63]                   big slow wave drifting one way
v += sine[(col*3 - row*4 - t/4) & 63]         diagonal wave drifting the other way
v += sine[(row*5 + col + col/4 + t/16) & 63]  very slow third wave
v += SKY_BIAS_ROW - row                        more clouds near the top
return v > 20 ? 2 : v > 14 ? 1 : 0
```

- **Sine table**: 64 bytes, one full wave scaled to −8..8 (made with `round(8*sin(2πi/64))`). `movsbq` loads a *signed* byte (sign-extend), unlike `movzbq`.
- **`& 63`** wraps any index into 0..63, so the wave repeats. It also works for negative numbers, because in two's complement the low 6 bits of −1 are 63.
- **Why three waves**: one wave looks like stripes. Waves with different periods (64, ~21, ~51 columns) and different speeds make blobs that change shape. With `col + col/4` the third wave doesn't line up with the first, so there's no visible repeating pattern across 120 columns. (In an earlier version two waves shared a period and you could see the sky repeat. That was the fix.)
- Clouds get colour pair 4 (slate grey #5f5f87), set in `draw_world`.

## `draw_game` (screens/fights.s)

This sets the layer order, back to front: `draw_world` (sky, platforms, water, slugcats) → `draw_rain` → `draw_spears` → the score with `mvprintw(0, 56, " %ld - %ld ", kills[0], kills[1])`. Like with `printf`, `%rax = 0` says no float arguments. `kills+8` is `kills[1]`.

## Colours (`main.s`)

`init_pair(n, fg, bg)` for 1 = P1 green (palette 150), 2 = P2 orange (209), 3 = water blue (4), 4 = clouds (60). The numbers are the nearest xterm-256 colours to the RGB values we picked, because macOS Terminal won't let a program set exact RGB. `TERM=xterm-256color` in `docker-compose.yml` makes the 256 colours available inside the container.

## Likely questions

- *Why sample 8 points and not just 1?* With 1 sample a cell is either fully on or off, so shapes jump a whole cell and look blocky. 8 samples give 9 brightness levels and smooth edges.
- *Why are samples 8 apart in both directions?* A cell is 16×32 subunits, so 2×4 samples are evenly spaced squares.
- *Cost?* 120·36·8 ≈ 35k `sample_point` calls per frame, each a few compares. That's easily fast enough at 30 fps.
- *Why is the sky only drawn in empty cells?* It's the background layer: anything with brightness > 0 is in front of it.

## Try it yourself (do at least one)

1. Change the ramp to `" .-~+=*#%@"` and look at the difference.
2. Make the slugcat edges harder: change the edge shade from 6 to 9.
3. Make the clouds move twice as fast (hint: the `shrq` amounts on `t`).
4. Add a 4th sine wave to the sky.
