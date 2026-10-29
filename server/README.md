# painworld-server

Play painworld in a browser. The game itself is untouched: this folder only
adds a small Go server around the finished assembly.

```
browser (xterm.js) ── websocket ── Go server ── PTY ── box64 ── painworld (x86-64)
```

- **Go server** (`main.go`, `game.go`): serves the page, and for every visitor
  starts one copy of the game in a 120x36 pseudo-terminal. Key presses go in,
  the screen comes back out.
- **Box64** runs the x86-64 game on ARM (the Raspberry Pi 5). Measured on the
  Pi: ~10% of one core per player, ~27 fps (native is ~30). qemu only managed
  ~14 fps.
- **The game** is built from the unchanged `src/` with
  `make final CC=x86_64-linux-gnu-gcc` (same Makefile, x86-64 cross compiler).

## Limits

| env var | default | what |
|---|---|---|
| `MAX_SESSIONS` | `6` | games running at once, more players get "server full" |
| `MAX_TIME` | `20m` | longest one game may run |
| `IDLE_TIME` | `3m` | no key press for this long ends the game |
| `ADDR` | `:8080` | where the server listens |

## Build and run locally (ARM64, e.g. a Mac)

```bash
docker build -f server/Dockerfile -t painworld-web .
docker run --rm -p 8080:8080 painworld-web
# open http://localhost:8080
```

The first build compiles Box64 (a few minutes on a Mac, ~15 min on the Pi).
Docker caches it after that, since it doesn't depend on the game.

## Deploy on the Pi (docker-compose)

```yaml
  painworld:
    container_name: painworld
    build:
      context: https://github.com/umarbektokyo/painworld.git#main
      dockerfile: server/Dockerfile
    expose:
      - "8080"
    environment:
      - MAX_SESSIONS=6
    read_only: true
    tmpfs:
      - /tmp:size=16m
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    pids_limit: 128
    mem_limit: 512m
    cpus: 2
    networks:
      - painworld     # NOT umbrella: can't reach vault & co, only the tunnel
    restart: unless-stopped
```

and the tunnel joins that network too:

```yaml
  tunnel:
    networks:
      - umbrella
      - painworld

networks:
  painworld:
    driver: bridge
```

plus one line in `data/tunnel/config.yml` (above the 404 rule), and the DNS
route for `painworld.umarbek.dev` in Cloudflare:

```yaml
  - hostname: painworld.umarbek.dev
    service: http://painworld:8080
```

No healthcheck: the image has no shell or wget on purpose. `/healthz` exists
if you want an external check.
