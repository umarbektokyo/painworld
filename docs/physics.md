# physics in C

The same logic as `physics.s`, written in C so it is easier to read. It is only a reference, it is not built. The function names and the order match `physics.s`.

```c
// physics.c - the C version of physics.s, only for reading (not built).
// every function here has a twin with the same name in physics.s, and the
// lines are in the same order, so you can read them side by side.
// the variables are the arrays from data.s, the numbers come from constants.inc.

// ---- from constants.inc ----
#define NUM_PLAYERS   2
#define NUM_CHUNKS    4     // P1 head, P1 body, P2 head, P2 body
#define NUM_PLATS     6
#define WORLD_W       1920
#define RUN_SPEED     32
#define RUN_ACCEL     2
#define FRICTION_MUL  3
#define FRICTION_DIV  4
#define GRAVITY       5
#define MAX_FALL      56
#define REST_LEN      64
#define SPINE_DIV     4

// ---- from data.s (each one is an array of 8-byte numbers = long) ----
extern long chunk_x[4], chunk_y[4], chunk_vx[4], chunk_vy[4], chunk_r[4];
extern long start_x[4], start_y[4], jump_kick[2];
extern long start_dir[2], move_dir[2], move_timer[2], jump_req[2];
extern long grab_req[2], on_ground[2], held_spear[2];
extern long plat_x0[6], plat_y0[6], plat_x1[6], plat_y1[6];

// ---- from the other files ----
void spawn_spears(void);       // spears.s
void grab_or_throw(long p);    // spears.s
void update_spears(void);      // spears.s
void reset_rain(void);         // rain.s
void update_rain(void);        // rain.s
void check_drowning(void);     // rain.s

static void spine(long p);
static long isqrt(long n);
static void collide_chunk(long i);

// slugcats back to the start, new spears, rain back to a drizzle.
// kills aren't reset, so the score carries over.
void reset_round(void)
{
    for (long i = 0; i < NUM_CHUNKS; i++) {        // every chunk
        chunk_x[i]  = start_x[i];                  //   back to the start
        chunk_y[i]  = start_y[i];
        chunk_vx[i] = 0;                           //   not moving
        chunk_vy[i] = 0;
    }
    for (long p = 0; p < NUM_PLAYERS; p++) {       // every player
        move_dir[p]   = start_dir[p];              //   P1 faces right, P2 left
        move_timer[p] = 0;                         //   not running
        jump_req[p]   = 0;                         //   forget old key presses
        grab_req[p]   = 0;
        on_ground[p]  = 0;                         //   in the air until we land
        held_spear[p] = -1;                        //   empty hands
    }
    spawn_spears();                                // new random spears
    reset_rain();                                  // drizzle again, no water
}

// one frame of the whole simulation
void update_physics(void)
{
    // 1. move every chunk
    for (long i = 0; i < NUM_CHUNKS; i++) {
        long p    = i / 2;                         // player: 0, 0, 1, 1
        long part = i % 2;                         // 0 = head, 1 = body

        // run or slow down (only a head whose player pressed a move key runs)
        if (part == 0 && move_timer[p] > 0)
            chunk_vx[i] += (move_dir[p] * RUN_SPEED - chunk_vx[i]) / RUN_ACCEL;
        else
            chunk_vx[i] = chunk_vx[i] * FRICTION_MUL / FRICTION_DIV;

        // jump: only if pressed AND standing on something
        if (jump_req[p] != 0 && on_ground[p] != 0)
            chunk_vy[i] = -jump_kick[part];        // head -64, body -50 (up = minus)

        // gravity, but never fall faster than MAX_FALL
        chunk_vy[i] += GRAVITY;
        if (chunk_vy[i] > MAX_FALL)
            chunk_vy[i] = MAX_FALL;

        // move
        chunk_x[i] += chunk_vx[i];
        chunk_y[i] += chunk_vy[i];
    }

    // 2. per player
    for (long p = 0; p < NUM_PLAYERS; p++) {
        spine(p);                                  // pull head + body together

        if (grab_req[p] != 0) {                    // spear key pressed?
            grab_or_throw(p);
            grab_req[p] = 0;
        }

        if (move_timer[p] > 0)                     // one frame of running used up
            move_timer[p]--;
        jump_req[p]  = 0;                          // the jump request is handled
        on_ground[p] = 0;                          // collide_chunk sets it again
    }

    // 3. collisions
    for (long i = 0; i < NUM_CHUNKS; i++)          // every chunk:
        collide_chunk(i);                          //   land on platforms, stay on screen

    // 4. spears, 5. rain + drowning
    update_spears();                               // held ones follow, thrown ones fly
    update_rain();                                 // drops, splashes, the lake rises
    check_drowning();                              // head under water -> round over
}

// spring between player p's head and body, fixes 1/4 of the stretch per frame
static void spine(long p)
{
    long head = p * 2;                             // P1: chunk 0, P2: chunk 2
    long body = p * 2 + 1;                         // P1: chunk 1, P2: chunk 3

    long dx = chunk_x[head] - chunk_x[body];       // from body to head
    long dy = chunk_y[head] - chunk_y[body];

    long d = isqrt(dx * dx + dy * dy);             // current length (pythagoras)
    if (d == 0)                                    // on top of each other,
        return;                                    // no direction to push in

    long div = d * SPINE_DIV;                      // d * 4
    long stretch = d - REST_LEN;                   // > 0 too long, < 0 too short

    long cx = dx * stretch / div;                  // how much to move in x
    long cy = dy * stretch / div;                  // ... and in y

    chunk_x[head]  -= cx;                          // head towards the body
    chunk_vx[head] -= cx;                          // (velocity too: that's
    chunk_y[head]  -= cy;                          //  what makes it springy)
    chunk_vy[head] -= cy;
    chunk_x[body]  += cx;                          // body towards the head
    chunk_vx[body] += cx;
    chunk_y[body]  += cy;
    chunk_vy[body] += cy;
}

// biggest r with r * r <= n, just counts up (d is only ~60-100)
static long isqrt(long n)
{
    long r = 0;                                    // start at 0
    while ((r + 1) * (r + 1) <= n)                 // does the next number still fit?
        r++;                                       //   yes -> try one higher
    return r;                                      // e.g. isqrt(6449) = 80
}

// land on a platform if we're falling and our bottom just crossed its top.
// coming from below = go through. then keep it inside the screen.
static void collide_chunk(long i)
{
    long r = chunk_r[i];                           // radius of this circle

    for (long j = 0; j < NUM_PLATS; j++) {         // check every platform
        if (chunk_vy[i] < 0)                       // going up -> pass through
            continue;
        if (chunk_x[i] < plat_x0[j] || chunk_x[i] >= plat_x1[j])
            continue;                              // not above this platform

        long bottom = chunk_y[i] + r;              // bottom of the circle now
        if (bottom < plat_y0[j])
            continue;                              // not there yet
        long bottom_before = bottom - chunk_vy[i]; // ... and last frame
        if (bottom_before > plat_y0[j])
            continue;                              // was already below: came from under

        chunk_y[i]  = plat_y0[j] - r;              // land: sit on top
        chunk_vy[i] = 0;
        on_ground[i / 2] = 1;
    }

    if (chunk_x[i] < r) {                          // left edge
        chunk_x[i]  = r;
        chunk_vx[i] = 0;
    }
    if (chunk_x[i] > WORLD_W - r) {                // right edge
        chunk_x[i]  = WORLD_W - r;
        chunk_vx[i] = 0;
    }
}
```
