# 2. Physics + procedural animation (`physics.s`)

Your job is to explain why the slugcats move the way they do: lean, stretch, squash, all without a single animation frame.

## The body

Each slugcat is **two circles** ("chunks"): a head (r = 42) and a body (r = 35). There are 4 chunks in total, index = `player * 2 + part`:

```
chunk 0 = P1 head   chunk 1 = P1 body   chunk 2 = P2 head   chunk 3 = P2 body
player = i >> 1  (shrq $1)        part = i & 1  (andq $1)
```

Each chunk has `x, y, vx, vy` in subunits (16 per cell width, 32 per cell height).

## The three rules that make the animation

1. **Only the head is driven by the keys.** The body only gets friction.
2. **The head gets a bigger jump kick than the body** (`jump_kick: JUMP_HEAD 64, JUMP_BODY 50`).
3. **A springy spine** pulls them back to `REST_LEN` (64) apart every frame.

So when you run, the head goes first and the spine drags the body along, which reads as a lean. On a jump the head shoots up faster, so it stretches. On landing the body stops, the head is still moving, and the spring brings them back together: squash and wobble. Nothing here is animated by hand; it all falls out of the physics.

## `update_physics`: one frame

**1. Move every chunk** (loop over i = 0..3, `rbx` = i, `r12` = player, `r13` = part)
- Running (head only, while `move_timer > 0`): `vx += (dir*RUN_SPEED - vx) / RUN_ACCEL`. Each frame closes half the gap to top speed, so it accelerates quickly and then levels off.
- Otherwise friction: `vx = vx * 3 / 4`. We use `idivq`, which rounds towards 0, so small speeds really reach 0. (`sarq` would round −1 down to −1 forever.)
- Jump: if `jump_req` and `on_ground`, then `vy = -jump_kick[part]` (negative is up).
- Gravity: `vy += 5`, capped at `MAX_FALL` 56.
- `x += vx`, `y += vy`.

**2. Per player:** `spine(p)`, handle `grab_req` (calls `grab_or_throw`, see spears), count down `move_timer`, clear `jump_req` and `on_ground`.

**3. Collisions:** `collide_chunk(i)` for each chunk sets `on_ground` again if it lands.

**4–5.** `update_spears`, `update_rain`, `check_drowning`.

`cqto` before every `idivq`: `idivq` divides the 128-bit number `rdx:rax`, so rdx has to hold the sign of rax (all 0s or all 1s). `cqto` does exactly that.

## `spine(p)`: the spring

```
dx = head.x - body.x,  dy = head.y - body.y
d  = isqrt(dx² + dy²)                    current length
k  = (d - REST_LEN) / (d * SPINE_DIV)    how far off, as a fraction, /4 per frame
cx = dx * (d - REST_LEN) / (d * 4)       (we multiply first, then divide, to keep precision)
head.x -= cx; head.vx -= cx;  body.x += cx; body.vx += cx    (same for y)
```
- `dx / d` is the direction (a unit vector), and `(d - REST_LEN)` is how much it's stretched. If it's too long (positive), the head moves back towards the body and the body towards the head; if it's too short (negative), they get pushed apart.
- Fixing only **1/4** per frame makes it soft. Changing the **velocity** too (not only the position) makes it bounce, a bit like a spring that remembers its motion. If you only moved positions it would feel like wet noodles; with 1/1 it would be a rigid stick.
- If `d == 0` there's no direction, so we skip (it would divide by zero).

## `isqrt(n)`

```
r = 0;  while ((r+1)² <= n) r++;  return r
```
It's the simplest correct integer square root. It's slow for huge numbers, but `d` is only ~60–100 and it runs twice per frame. This is the only square root in the whole game; everything else compares squared distances.

## `collide_chunk(i)`: one-way platforms

A chunk lands on platform j only if:
- it's falling (`vy >= 0`). Going up, it passes through, which is how you jump up through platforms;
- its x is between `x0` and `x1`;
- its bottom (`y + r`) is now at or past the top `y0`;
- **and** its bottom last frame (`y + r - vy`) was at or above `y0`.

Then `y = y0 - r`, `vy = 0`, `on_ground = 1`. The "was above last frame" check stops it snapping onto a platform it's falling *beside*. It also can't tunnel, even at high speed, because we compare before and after instead of checking overlap.

Then the screen edges: clamp x to `[r, WORLD_W - r]` and zero `vx`.

Standing still works like this: every frame gravity pushes `vy` to 5, the chunk moves 5 into the platform, and `collide_chunk` puts it back on top with `on_ground = 1`.

## `reset_round`

This copies `start_x/start_y` into the chunks, zeroes the velocities, resets per-player state (`held_spear = -1`), then calls `spawn_spears` and `reset_rain`. `kills` is not reset, so the score carries over.

## Tuning values (`constants.inc`)

| | value | effect |
|---|---|---|
| `RUN_SPEED` | 32 | 2 cells per frame |
| `RUN_ACCEL` | 2 | reaches top speed in ~3 frames |
| `FRICTION` | 3/4 | stops quickly |
| `GRAVITY` | 5 | snappy arcs |
| `JUMP_HEAD/BODY` | 64 / 50 | height ~10 rows, the difference = stretch |
| `REST_LEN` | 64 | spine length (4 cells) |
| `SPINE_DIV` | 4 | spring stiffness |

Jump height ≈ v²/2g = 64²/10 ≈ 410 subunits for the head alone; the spine pulls that down a bit. Platforms are 192 apart, so one jump easily reaches the next.

## Likely questions

- *Why not just draw a sprite?* Because then it can't stretch or wobble. Physics plus the sampler gives animation for free, and it's less code than writing frames.
- *Why integers?* No need for floats: subunits give sub-cell precision, and integer instructions are the ones we know from the course.
- *Why does the body have friction but never runs?* So that it's dragged, not driven. That creates the lean.
- *What happens if both circles end up on the same spot?* `d = 0`, and the spine skips that frame.

## Try it yourself

1. Set `JUMP_HEAD` = `JUMP_BODY` (both 57): the stretch goes away. Explain why.
2. `SPINE_DIV` 4 → 10: a floppy slugcat. → 1: a rigid one.
3. Make the body run too (remove the `cmpq $1, %r13` check) and see the lean disappear.
4. Change `REST_LEN` to 30: a short, round slugcat.
