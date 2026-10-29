# syntax=docker/dockerfile:1
#
# painworld for the web, on ARM64 (Raspberry Pi 5, or a Mac for testing).
# build from the repo root:  docker build -f server/Dockerfile -t painworld-web .
#
# 1. box64   - x86-64 -> ARM64 emulator (only rebuilt when BOX64_REF changes)
# 2. game    - the unchanged assembly, cross-built with `make final`
# 3. server  - the Go web server + xterm.js
# 4. runtime - distroless: no shell, no package manager, runs as nonroot

ARG BOX64_REF=v0.4.4
ARG BOX64_TARGET=RPI5ARM64
ARG XTERM_VERSION=6.0.0

# ---- 1. box64 ---------------------------------------------------------------
FROM debian:trixie AS box64
ARG BOX64_REF
ARG BOX64_TARGET
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates cmake make gcc g++ python3 \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${BOX64_REF}" https://github.com/ptitSeb/box64 /box64
WORKDIR /box64/build
RUN cmake .. -D${BOX64_TARGET}=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
 && make -j"$(nproc)" \
 && strip box64

# ---- 2. game ----------------------------------------------------------------
FROM debian:trixie AS game
RUN dpkg --add-architecture amd64 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc-x86-64-linux-gnu libc6-dev-amd64-cross libncurses-dev:amd64 make ncurses-base \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /game
COPY Makefile ./
COPY src ./src
# same Makefile as always, only the compiler is swapped for the x86-64 cross one
RUN make final CC=x86_64-linux-gnu-gcc
# the static ncurses inside the game still reads two things at runtime:
# the terminal description, and the C.UTF-8 locale (main.s calls setlocale,
# without it the title's block characters come out as garbage)
RUN mkdir -p /out/terminfo/x \
 && cp "$(find /lib/terminfo /usr/share/terminfo -name xterm-256color | head -1)" /out/terminfo/x/ \
 && cp -r /usr/lib/locale/C.utf8 /out/C.utf8

# ---- 3. server --------------------------------------------------------------
FROM golang:1.26 AS server
ARG XTERM_VERSION
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN mkdir -p web/vendor /tmp/xterm \
 && curl -fsSL "https://registry.npmjs.org/@xterm/xterm/-/xterm-${XTERM_VERSION}.tgz" | tar xz -C /tmp/xterm \
 && cp /tmp/xterm/package/lib/xterm.js /tmp/xterm/package/css/xterm.css web/vendor/
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/painworld-server .

# ---- 4. runtime -------------------------------------------------------------
FROM gcr.io/distroless/cc-debian13:nonroot
COPY --from=box64  /box64/build/box64      /usr/local/bin/box64
COPY --from=game   /game/painworld         /opt/painworld/painworld
COPY --from=game   /out/terminfo           /usr/share/terminfo
COPY --from=game   /out/C.utf8             /usr/lib/locale/C.utf8
COPY --from=server /out/painworld-server   /usr/local/bin/painworld-server
ENV GAME_CMD="/usr/local/bin/box64 /opt/painworld/painworld"
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/usr/local/bin/painworld-server"]
