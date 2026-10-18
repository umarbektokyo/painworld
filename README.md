# painworld
It's like rain world but was made using assembly, thus in pain.

```
                      ███                                                   ████      █████
                     ▒▒▒                                                   ▒▒███     ▒▒███ 
 ████████   ██████   ████  ████████      █████ ███ █████  ██████  ████████  ▒███   ███████ 
▒▒███▒▒███ ▒▒▒▒▒███ ▒▒███ ▒▒███▒▒███    ▒▒███ ▒███▒▒███  ███▒▒███▒▒███▒▒███ ▒███  ███▒▒███ 
 ▒███ ▒▒▒   ███████  ▒███  ▒███ ▒███     ▒███ ▒███ ▒███ ▒███ ▒███ ▒███ ▒▒▒  ▒███ ▒███ ▒███ 
 ▒███      ███▒▒███  ▒███  ▒███ ▒███     ▒▒███████████  ▒███ ▒███ ▒███      ▒███ ▒███ ▒███ 
 █████    ▒▒████████ █████ ████ █████     ▒▒████▒████   ▒▒██████  █████     █████▒▒████████
▒▒▒▒▒      ▒▒▒▒▒▒▒▒ ▒▒▒▒▒ ▒▒▒▒ ▒▒▒▒▒       ▒▒▒▒ ▒▒▒▒     ▒▒▒▒▒▒  ▒▒▒▒▒     ▒▒▒▒▒  ▒▒▒▒▒▒▒▒ 
```

## Specs
Start Date: October 14th
Deadline: October 20th
Language: x86-64 assembly, AT&T Syntax. Linked with libc + ncursesw (no floats, everything is integer math).
Terminal: at least 120 x 36 characters, 256 colours (falls back to 8 colours).

## The Game
Two slugcats, one keyboard, one static multi-floor map.
- **Move**: run left/right and jump. Platforms can be jumped through from below and landed on from above.
- **Spears**: spears spawn at random spots on the platforms. Walk onto one and press your spear key to pick it up, press it again to throw it the way you are facing. It flies in a shallow arc and sticks into whatever platform it lands on, so it can be picked up again. A hit kills.
- **Rain**: it starts as a light drizzle and gets heavier every second. A drop that lands on dry floor disappears after a second, but rain landing on rain stays. Puddles turn into a lake that keeps rising. Rain hitting a platform leaves a thin layer of water on top (it gets thicker the harder it rains) and drips off its edges. If your head goes under water, you drown.
- **Rounds**: spear the other slugcat (or let them drown) to win the round. Both drowning at once is a draw. The kill count carries over between rounds.

### Controls
| | P1 (green) | P2 (orange) |
|---|---|---|
| run | `a` / `d` | `←` / `→` |
| jump | `w` | `↑` |
| stop | `s` | `↓` |
| grab / throw spear | `q` | `.` |

Menu: `Enter` start, `g` guide, `c` credits. `x` or `Esc` quits from anywhere.

### Scenes
- Home screen (title + menu)
- Fight screen
- End-of-round screen with the winner and kill count
- Guide screen explaining the controls
- Credits screen

## How It Works
### Procedural animation
Each slugcat is two circles, a head and a body, joined by a springy "spine". Only the head is driven by the keys, and the spine drags the body along. A jump kicks the head harder than the body. That's all it takes for the slugcat to lean when it runs, stretch when it jumps, and squash and wobble when it lands, without any animation frames.

### Rendering (the brightness sampler)
For every character cell, 8 points inside the cell (2 across, 4 down) are tested against the world: platforms, water and the slugcats' circles (centre = brightest). The average brightness picks a character from the ramp ` .:-=+*#%@`. A cell that is only partly covered gets a dimmer character, which is what makes the shapes look smooth. Spears, raindrops and text are drawn on top as plain characters.

### Units
Positions and speeds are stored in subunits: 16 subunits = 1 cell wide, and a cell is 32 subunits tall (cells are about twice as tall as they are wide). That gives sub-cell movement without floats.

### Frame loop (~30 FPS)
read all pending keys → update physics (move, spine, collisions, spears, rain, drowning) → draw the current scene → `refresh()` → `usleep(33000)`.

## Project Structure
```
.
├── Dockerfile / docker-compose.yml   # linux/amd64 dev container
├── Makefile                          # builds src/**/*.s into build/, links ncursesw
└── src
    ├── constants.inc                 # every .equ (sizes, physics, keys)
    ├── data.s                        # all game state (arrays of 8-byte values)
    ├── main.s                        # ncurses setup, main loop, scene dispatch
    ├── inputs.s                      # keys -> player actions / scene changes
    ├── render.s                      # brightness sampler (draw_world, sample_point)
    ├── spears.s                      # spawn, grab/throw, flight, hits, drawing
    ├── rain.s                        # drops, splashes, flood, drowning
    └── screens
        ├── fights.s                  # physics step, spine, collisions, round reset, HUD
        ├── end.s                     # end-of-round screen
        ├── home.s / guide.s / credits.s
        └── text.s                    # draw_lines helper for the menu screens
```

## Usage Guide (mac)
```bash
# Ensure docker desktop is up and running
# Notice that you can edit files under src/,
# and they will automatically sync to the docker container!

# start docker container
docker compose up -d
# to stop the docker container, run:
docker compose down

# get into the container
docker exec -it rain /bin/bash
# to exit the container (at the end of the development, just type in:)
exit

# Build (assembles src/**/*.s into build/, links with ncursesw)
make

# Build and run (make the terminal at least 120 x 36 first)
make run
```
