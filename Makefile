# Makefile
# =============================================================================
# painworld -- build
#
# Assembles every src/**/*.s (except src/experiments/) into build/ and links
# them with ncurses. Runs inside the Docker container (linux/amd64).
#
# Usage (inside the container):
#   make        # build ./rain
#   make run    # build and run
#   make clean  # remove build/ and the binary
# =============================================================================

CC      = gcc
ASFLAGS = -no-pie -g -Isrc          # -Isrc lets .include "constants.inc" work
LDLIBS  = -lncurses -ltinfo
SRC     = $(shell find src -name '*.s' -not -path 'src/experiments/*')
OBJ     = $(patsubst src/%.s,build/%.o,$(SRC))
BIN     = rain

.PHONY: all run clean

all: $(BIN)

$(BIN): $(OBJ)
	$(CC) -no-pie -g -o $@ $^ $(LDLIBS)

build/%.o: src/%.s src/constants.inc
	mkdir -p $(dir $@)
	$(CC) $(ASFLAGS) -c $< -o $@

run: $(BIN)
	./$(BIN)

clean:
	rm -rf build $(BIN)
