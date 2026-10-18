# painworld: team overview

Everyone reads this. Then each person takes one deep-dive and owns explaining it:

| Area | Files | Guide |
|---|---|---|
| Rendering + sky | `render.s`, `sky.s`, `screens/fights.s` | [1-rendering.md](1-rendering.md) |
| Physics + procedural animation | `physics.s` | [2-physics.md](2-physics.md) |
| Spears + inputs | `spears.s`, `inputs.s` | [3-spears-inputs.md](3-spears-inputs.md) |
| Rain/flood + main loop + screens | `rain.s`, `main.s`, `screens/*` | [4-rain-screens.md](4-rain-screens.md) |

Owning an area means you can explain every line in it and answer "why this way?". Everyone should still be able to answer the questions at the bottom of this page.

---

## 1. What the game is

Two slugcats on one keyboard, one static 120×36 map with 6 platforms. Spear the other one to win the round. Meanwhile the rain gets heavier and the floor floods; whoever's head goes under drowns. Scenes: home → fight → end-of-round, plus guide and credits.

## 2. How a frame works (`main.s`)

```
main:
    setlocale, initscr, ...           ncurses setup, colour pairs, srand
    reset_round                       place slugcats, spears, reset rain
loop (~30 times per second):
    poll_input                        read ALL keys pressed since last frame
    frame_count++
    erase                             clear ncurses' screen buffer
    if terminal < 120x36: print a message
    else by game_state:
        GAME:    update_physics, draw_game
        END:     draw_end              (no physics -> the scene is frozen)
        HOME / GUIDE / CREDITS: draw_home / draw_guide / draw_credits
    refresh                           ncurses sends only what changed
    usleep(33000)
```

The simulation and the drawing are separate. `update_physics` only changes numbers in `data.s`, and the draw functions only read them.

## 3. Who calls what

```
main ── poll_input ─────────────── (reset_round on Enter)
     ├─ update_physics ─┬─ spine ── isqrt
     │                  ├─ grab_or_throw
     │                  ├─ collide_chunk
     │                  ├─ update_spears ── find_platform
     │                  ├─ update_rain ──── spawn_drop, find_platform
     │                  └─ check_drowning
     ├─ draw_game ──────┬─ draw_world ── sample_point ── find_platform
     │                  │               └ sky_shade
     │                  ├─ draw_rain
     │                  └─ draw_spears
     ├─ draw_end  (draw_world, draw_rain, draw_spears + text)
     └─ draw_home / draw_guide / draw_credits ── draw_lines
reset_round ── spawn_spears, reset_rain
```

## 4. Data: everything is a global array (`data.s`)

There's no `malloc` and there are no structs. Every piece of state is a global array of 8-byte numbers (`.quad`), and arrays that belong together share an index:

```asm
chunk_x:  .quad 0, 0, 0, 0      # chunk 0 = P1 head, 1 = P1 body, 2 = P2 head, 3 = P2 body
movq chunk_x(,%rcx,8), %rax     # rax = chunk_x[rcx]   (address = chunk_x + rcx*8)
```

- **chunks** (4): `chunk_x/y/vx/vy/r`. Index = `player * 2 + part`, so `player = i >> 1` and `part = i & 1`.
- **players** (2): `move_dir`, `move_timer`, `jump_req`, `grab_req`, `on_ground`, `held_spear`, `kills`.
- **spears** (6): `spear_x/y/vx/vy/state/owner/dir`.
- **rain**: `drop_x/y/active` (1024), `splash` (one per column), `plat_wet` (one per platform), `water_total`, `water_level`, `rain_level`.
- **platforms** (6): `plat_x0/y0/x1/y1` rectangles. Platform 0 is the floor.

All `.equ` constants live in `constants.inc`, which every file `.include`s.

## 5. Units: subunits instead of floats

There are no floats anywhere. Positions are stored in **subunits**: a cell is 16 subunits wide and 32 tall, because a terminal cell is about twice as tall as it is wide. So moving 4 subunits per frame means a quarter of a cell per frame, which gives smooth slow motion with integers only. To get from a position to a screen cell: `col = x >> 4`, `row = y >> 5`. The world is 1920 × 1152 subunits, and y points down.

## 6. Conventions used everywhere (learn these, they come up in every file)

- **System V calling convention.** Arguments go in `%rdi, %rsi, %rdx, %rcx, %r8, %r9`, and the result comes back in `%rax`. This applies to our functions and to the C ones (`mvaddch(row, col, ch)` = `rdi, rsi, rdx`).
- **Callee-saved registers** (`%rbx, %r12–%r15`): if a function uses them, it `push`es them at the start and `pop`s them at the end, in reverse order. That's the `# callee-conventions` block. We use them for loop counters that must survive a `call`.
- **Caller-saved registers** (`%rax, %rcx, %rdx, %rsi, %rdi, %r8–%r11`) can be destroyed by any `call`. That's why loop counters around calls live in `%rbx`/`%r12...`.
- **Stack alignment.** `%rsp` must be a multiple of 16 when you `call` a C function. On entry the return address makes it 8 off, and `pushq %rbp` fixes that. Every extra `push` shifts it by 8 again, so with an **odd** number of extra pushes we add `subq $8, %rsp`. You'll see that in `poll_input`, `draw_world`, `update_physics` and others.
- **`-no-pie` + absolute addresses.** We link with `-no-pie`, so the program sits at a fixed address and we can write `$label` (address as a number) and `label(,%rcx,8)`, like in the coursework.
- **Division.** `idivq %rcx` divides the 128-bit `rdx:rax` by rcx. So first `cqto` (sign-extend rax into rdx) for signed values, or `movq $0, %rdx` for unsigned `divq`. The quotient ends up in `%rax` and the remainder in `%rdx`. `rand() % n` is just the remainder.
- **`movl %eax, %eax` after `rand()`.** `rand` returns a 32-bit int, and the top half of rax is undefined. Writing a 32-bit register zeroes the upper half.
- **`COLOR_PAIR(n)` is `n << 8`.** An ncurses `chtype` holds the character in the low 8 bits and attributes above that, so `ch | (pair << 8)` gives a coloured char.

## 7. Libraries we call

- **ncursesw** (the UTF-8 version of ncurses): `initscr, noecho, cbreak, keypad, curs_set, timeout, set_escdelay, start_color, init_pair, getch, erase, mvaddch, mvaddstr, mvprintw, attron, attroff, getmaxx/y, refresh, endwin`
- **libc**: `setlocale, time, srand, rand, usleep`

## 8. How we built it (good for the HCI part of the talk)

`git log` shows the actual process. We agreed on the scope first, then built in thin playable steps, testing after each one: build fix → two circles through the sampler → spine → spears + end screen → rain/flood → menus → polish (colours, bigger map, heavier rain, drips, wet platforms, sky, snappier physics) → cleanup. Claude wrote most of the assembly from our design decisions. We tested every step, rejected or changed things (dropped ropes and lying down; the V-shaped lake became a flat lake; the "spear falls short" arc got re-tuned), and then studied the code until each of us could explain our part.

## 9. Questions every one of us should be able to answer

1. Walk through one frame, from key press to pixels.
2. Why subunits, and why is a cell 16×32?
3. What is `chunk_x(,%rcx,8)` and how does `player*2 + part` work?
4. Why `pushq %rbx` at the top of some functions, and why `subq $8, %rsp` in some of them?
5. What does `cqto` do and why is it before `idivq`?
6. How does the game know you're "holding" a key, when terminals only report key presses?
7. Why does the slugcat stretch when it jumps? (head and body get different kicks, plus the spine)
8. How does a shape become ASCII? (8 samples per cell, averaged, mapped onto a ramp)
9. How does the flood start and why does it get faster?
10. Why ncursesw instead of writing escape codes ourselves? (it diffs frames, handles keys and colours, so less code)
