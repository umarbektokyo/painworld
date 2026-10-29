// connects xterm.js to the game running on the server.
// keys go up the websocket, the game's screen comes back down it.
(function () {
  "use strict";

  var COLS = 120, ROWS = 36;  // the game needs exactly this size

  // catppuccin mocha. the game still asks for the same colour numbers
  // (see init_pair in main.s), we only decide here what they look like.
  var MOCHA = {
    crust: "#11111b", text: "#cdd6f4", overlay1: "#7f849c",
    green: "#a6e3a1", peach: "#fab387", blue: "#89b4fa"
  };

  // xterm.js only lets you restyle colours 16..255 as one whole list, so
  // build the normal xterm-256 list and swap in the three the game uses
  function palette256() {
    var levels = [0, 95, 135, 175, 215, 255], list = [];
    function hex(r, g, b) {
      return "#" + [r, g, b].map(function (v) { return ("0" + v.toString(16)).slice(-2); }).join("");
    }
    for (var i = 16; i < 232; i++) {      // 6x6x6 colour cube
      var n = i - 16;
      list.push(hex(levels[Math.floor(n / 36)], levels[Math.floor(n / 6) % 6], levels[n % 6]));
    }
    for (var g = 0; g < 24; g++) {        // greys
      var v = 8 + g * 10;
      list.push(hex(v, v, v));
    }
    list[150 - 16] = MOCHA.green;  // P1_COLOR
    list[209 - 16] = MOCHA.peach;  // P2_COLOR
    list[60 - 16]  = MOCHA.overlay1; // SKY_COLOR, the clouds
    return list;
  }

  var term = new Terminal({
    cols: COLS,
    rows: ROWS,
    fontFamily: 'Menlo, Consolas, "DejaVu Sans Mono", monospace',
    fontSize: 14,
    scrollback: 0,
    cursorBlink: false,
    theme: {
      background: MOCHA.crust,
      foreground: MOCHA.text,   // platforms, menu text, spears
      black: MOCHA.crust,       // the game uses colour 0 as background everywhere
      blue: MOCHA.blue,         // colour 4: rain and water
      cursor: MOCHA.crust,      // the game hides the cursor, keep it invisible
      extendedAnsi: palette256()
    }
  });
  term.open(document.getElementById("terminal"));

  // the terminal always stays 120 x 36 cells, only the font size changes
  // so the whole thing fits the window
  function fit() {
    var main = document.querySelector("main");
    var w = main.clientWidth - 16, h = main.clientHeight - 16;
    // a monospace cell is ~0.6 font-size wide and ~1.2 font-size tall
    var size = Math.floor(Math.min(w / (COLS * 0.6), h / (ROWS * 1.2)));
    term.options.fontSize = Math.max(6, Math.min(size, 22));
  }
  window.addEventListener("resize", fit);
  fit();

  var overlay = document.getElementById("overlay");
  var message = document.getElementById("message");
  document.getElementById("again").addEventListener("click", function () {
    location.reload();
  });

  function show(text) {
    message.textContent = text;
    overlay.hidden = false;
  }

  var scheme = location.protocol === "https:" ? "wss://" : "ws://";
  var ws = new WebSocket(scheme + location.host + location.pathname.replace(/[^/]*$/, "") + "play");
  ws.binaryType = "arraybuffer";

  ws.onopen = function () { term.focus(); };
  ws.onmessage = function (e) { term.write(new Uint8Array(e.data)); };
  ws.onclose = function (e) { show(e.reason || "disconnected"); };

  // every key press xterm.js sees goes to the game (arrows arrive as
  // escape sequences, ncurses turns them back into KEY_LEFT etc)
  term.onData(function (data) {
    if (ws.readyState === WebSocket.OPEN) ws.send(data);
  });
})();
