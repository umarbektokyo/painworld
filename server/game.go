package main

import (
	"context"
	"log"
	"net/http"
	"os/exec"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/creack/pty"
)

// the game needs exactly 120 x 36 (constants.inc), so every terminal is that size
const (
	termCols = 120
	termRows = 36
)

// environment for the game process. nothing from the visitor ends up here.
var gameEnv = []string{
	"TERM=xterm-256color", // 256 colours, like in the dev container
	"LANG=C.UTF-8",
	"HOME=/tmp",           // box64 looks for a config file in HOME
	"BOX64_LOG=0",         // box64 must not print anything into the game screen
	"BOX64_NOBANNER=1",
}

// websocket close codes 4000-4999 are free for apps, the page shows the reason
const (
	closeFull websocket.StatusCode = 4000
	closeIdle websocket.StatusCode = 4001
	closeTime websocket.StatusCode = 4002
)

// playGame runs one game for one browser tab, from the websocket handshake
// until the game quits, the player leaves, or a limit is hit.
func playGame(server context.Context, w http.ResponseWriter, r *http.Request, cfg config, slots chan struct{}) {
	conn, err := websocket.Accept(w, r, nil) // nil options = only same-origin pages may connect
	if err != nil {
		return
	}
	conn.SetReadLimit(4096) // key presses are tiny, anything bigger is not a keyboard

	// take a slot, or tell the player we're full
	select {
	case slots <- struct{}{}:
		defer func() { <-slots }()
	default:
		conn.Close(closeFull, "the server is full, try again in a minute")
		return
	}

	// game lives at most maxTime, and dies early if the server shuts down
	game, cancel := context.WithTimeout(server, cfg.maxTime)
	defer cancel()

	// first reason to end the game wins, that's what the player gets told
	var once sync.Once
	code, reason := websocket.StatusNormalClosure, "game over"
	end := func(c websocket.StatusCode, why string) {
		once.Do(func() { code, reason = c, why })
		cancel()
	}

	// start the game in a fresh 120x36 pseudo-terminal
	cmd := exec.Command(cfg.game[0], cfg.game[1:]...)
	cmd.Env = gameEnv
	tty, err := pty.StartWithSize(cmd, &pty.Winsize{Cols: termCols, Rows: termRows})
	if err != nil {
		log.Printf("could not start the game: %v", err)
		conn.Close(websocket.StatusInternalError, "could not start the game")
		return
	}
	started := time.Now()
	log.Printf("game started, %d/%d playing", len(slots), cap(slots))

	// no key press for idleTime -> end the game
	idle := time.AfterFunc(cfg.idleTime, func() { end(closeIdle, "kicked for being idle") })
	defer idle.Stop()

	// game -> browser: whatever the game draws goes straight to xterm.js
	go func() {
		buf := make([]byte, 32*1024)
		for {
			n, err := tty.Read(buf)
			if n > 0 {
				wctx, wcancel := context.WithTimeout(context.Background(), 10*time.Second)
				werr := conn.Write(wctx, websocket.MessageBinary, buf[:n])
				wcancel()
				if werr != nil {
					end(websocket.StatusNormalClosure, "disconnected")
					return
				}
			}
			if err != nil { // the game exited (x / Esc), the pty is closed
				end(websocket.StatusNormalClosure, "thanks for playing!")
				return
			}
		}
	}()

	// browser -> game: key presses go into the pty like typing on a keyboard
	go func() {
		for {
			_, data, err := conn.Read(context.Background()) // returns once conn is closed
			if err != nil {
				end(websocket.StatusNormalClosure, "disconnected")
				return
			}
			idle.Reset(cfg.idleTime)
			if _, err := tty.Write(data); err != nil {
				end(websocket.StatusNormalClosure, "game over")
				return
			}
		}
	}()

	<-game.Done() // wait until something above (or a limit) ends the game
	switch {
	case server.Err() != nil:
		end(websocket.StatusGoingAway, "the server is restarting, try again soon")
	case game.Err() == context.DeadlineExceeded:
		end(closeTime, "time's up, refresh to play again")
	}

	// stop the game, then tell the browser why
	cmd.Process.Kill()
	cmd.Wait()
	tty.Close()
	conn.Close(code, reason)
	log.Printf("game ended after %s: %s", time.Since(started).Round(time.Second), reason)
}
