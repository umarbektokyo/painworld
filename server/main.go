// painworld-server: serves the finished painworld game to browsers.
//
// Every visitor gets their own copy of the game, started inside a
// pseudo-terminal (PTY). The browser shows that terminal with xterm.js and
// a websocket carries key presses in and screen output back out.
//
// The game itself is untouched: it's the static x86-64 binary from
// `make final`, run through Box64 so it works on ARM (the Raspberry Pi).
package main

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

//go:embed web
var webFiles embed.FS

// config comes from environment variables, with defaults that fit the Pi.
type config struct {
	addr        string        // where to listen
	game        []string      // command that starts one game
	maxSessions int           // games running at the same time
	maxTime     time.Duration // longest a single game may run
	idleTime    time.Duration // kick a player after this long without a key press
}

func loadConfig() config {
	return config{
		addr:        env("ADDR", ":8080"),
		game:        strings.Fields(env("GAME_CMD", "/usr/local/bin/box64 /opt/painworld/painworld")),
		maxSessions: envInt("MAX_SESSIONS", 6),
		maxTime:     envDuration("MAX_TIME", 20*time.Minute),
		idleTime:    envDuration("IDLE_TIME", 3*time.Minute),
	}
}

func main() {
	cfg := loadConfig()

	// a buffered channel used as a counter: putting something in takes a
	// slot, taking it out frees it. when it's full, the server is full.
	slots := make(chan struct{}, cfg.maxSessions)

	// cancelled on shutdown, so every running game gets stopped
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	static, err := fs.Sub(webFiles, "web")
	if err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()
	mux.Handle("GET /", http.FileServerFS(static))
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok\n"))
	})
	mux.HandleFunc("GET /status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]int{"playing": len(slots), "max": cap(slots)})
	})
	mux.HandleFunc("GET /play", func(w http.ResponseWriter, r *http.Request) {
		playGame(ctx, w, r, cfg, slots)
	})

	srv := &http.Server{
		Addr:              cfg.addr,
		Handler:           securityHeaders(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(shutdown)
	}()

	log.Printf("painworld-server on %s: %d games max, %s per game, %s idle kick, game = %q",
		cfg.addr, cfg.maxSessions, cfg.maxTime, cfg.idleTime, cfg.game)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

// securityHeaders: everything (scripts, styles, the websocket) comes from
// this server only. the page may be embedded in an iframe on umarbek.dev.
// inline styles are allowed because xterm.js sizes its rows by injecting
// css; scripts stay 'self' only, that's the part that stops injected code.
func securityHeaders(next http.Handler) http.Handler {
	csp := strings.Join([]string{
		"default-src 'self'",
		"style-src 'self' 'unsafe-inline'",
		"connect-src 'self'",
		"img-src 'self' data:",
		"frame-ancestors 'self' https://umarbek.dev",
		"base-uri 'none'",
		"form-action 'none'",
	}, "; ")
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Security-Policy", csp)
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if n, err := strconv.Atoi(os.Getenv(key)); err == nil && n > 0 {
		return n
	}
	return def
}

func envDuration(key string, def time.Duration) time.Duration {
	if d, err := time.ParseDuration(os.Getenv(key)); err == nil && d > 0 {
		return d
	}
	return def
}
