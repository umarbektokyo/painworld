# Usage (inside the container):
#   make        # build ./rain
#   make run    # build and run
#   make final  # build ./painworld, one static binary for submitting
#   make clean  # remove build/ and the binaries
# =============================================================================

CC      = gcc
ASFLAGS = -no-pie -g -Isrc          # -Isrc lets .include "constants.inc" work
LDLIBS  = -lncursesw -ltinfo         # ncursesw = ncurses with UTF-8 support
SRC     = $(shell find src -name '*.s' -not -path 'src/experiments/*')
OBJ     = $(patsubst src/%.s,build/%.o,$(SRC))
BIN     = rain
FINAL   = painworld

.PHONY: all run final clean

all: $(BIN)

$(BIN): $(OBJ)
	$(CC) -no-pie -g -o $@ $^ $(LDLIBS)

# same objects, but -static copies ncurses + libc into the binary
# (runs on any x86-64 linux), -s strips debug info to keep it smaller
final: $(FINAL)

$(FINAL): $(OBJ)
	$(CC) -no-pie -static -s -o $@ $^ $(LDLIBS)

build/%.o: src/%.s src/constants.inc
	mkdir -p $(dir $@)
	$(CC) $(ASFLAGS) -c $< -o $@

run: $(BIN)
	./$(BIN)

clean:
	rm -rf build $(BIN) $(FINAL)
