# seems liek in temrinal we can only say "a key was typed", never "released". 
# so a move key sets move_timer = KEY_HOLD and key is down while it's > 0. 
# holding the key auto-repeats, which keeps refilling it.
#
#   P1: a/d run, w jump, s stop, q spear      P2: arrows, . spear
#   Enter: start / next round / back, g: guide, c: credits, x: quit, ESC: quit

    .include "constants.inc"

    .text
    .globl poll_input

# void poll_input(void)
# reads keys until getch says there are none left (-1), so if 3 keys were
# pressed since last frame we handle all 3 now.
# it doesn't move anything itself, it only writes "requests" into data.s
# (move_dir, move_timer, jump_req, grab_req) and physics.s acts on them.
# %rcx = which player the key belongs to (0 or 1), so both share the same code.
poll_input:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx
    subq  $8, %rsp

.read_key:
    call getch                  # eax = next key code, -1 = nothing left
    cmpl $-1, %eax
    je   .no_more_keys          # no keys left -> we're done for this frame
    movl %eax, %ebx

    # keys that work in every scene
    cmpq $'x', %rbx             # 'x' = 120
    je   .quit
    cmpq $KEY_ESC, %rbx         # Esc = 27
    je   .quit
    cmpq $KEY_NEWLINE, %rbx     # Enter = 10
    je   .enter
    cmpq $'g', %rbx             # guide
    je   .guide
    cmpq $'c', %rbx             # credits
    je   .credits

    # P1 keys: set rcx = 0 first, then jump to the shared code
    movq $0, %rcx               # rcx = player 0
    cmpq $'a', %rbx
    je   .move_left
    cmpq $'d', %rbx
    je   .move_right
    cmpq $'w', %rbx
    je   .jump
    cmpq $'s', %rbx
    je   .stop
    cmpq $'q', %rbx
    je   .grab

    # P2 keys: same jumps, just rcx = 1
    movq $1, %rcx               # rcx = player 1
    cmpq $KEY_LEFT, %rbx        # 260, keypad() in main.s makes arrows one code
    je   .move_left
    cmpq $KEY_RIGHT, %rbx       # 261
    je   .move_right
    cmpq $KEY_UP, %rbx          # 259
    je   .jump
    cmpq $KEY_DOWN, %rbx        # 258
    je   .stop
    cmpq $'.', %rbx
    je   .grab

    jmp  .read_key              # some other key, ignore it, read the next one

# everything below writes into array[player], address = array + rcx * 8

.move_left:
    movq $-1, move_dir(,%rcx,8)         # move_dir[p] = -1, face left
    movq $KEY_HOLD, move_timer(,%rcx,8) # move_timer[p] = 12, run for 12 frames
    jmp  .read_key                      # (physics counts it down each frame)

.move_right:
    movq $1, move_dir(,%rcx,8)          # move_dir[p] = 1, face right
    movq $KEY_HOLD, move_timer(,%rcx,8) # move_timer[p] = 12
    jmp  .read_key

.jump:
    movq $1, jump_req(,%rcx,8)          # jump_req[p] = 1, physics only jumps
                                        # if we're on the ground
    # tapping w while holding d stops d from repeating, so a jump while running refills the run timer
    cmpq $0, move_timer(,%rcx,8)        # were we running?
    jle  .read_key                      # no: just the jump
    movq $KEY_HOLD, move_timer(,%rcx,8) # yes: keep running
    jmp  .read_key

.stop:
    movq $0, move_timer(,%rcx,8)        # move_timer[p] = 0, friction stops us
    jmp  .read_key

.grab:
    movq $1, grab_req(,%rcx,8)          # grab_req[p] = 1, physics decides if
    jmp  .read_key                      # it's a grab or a throw (spears.s)

# Enter means something different on each screen
.enter:
    cmpq $SCENE_HOME, game_state        # menu -> start a round
    je   .start_round
    cmpq $SCENE_END, game_state         # end screen -> next round
    je   .start_round
    cmpq $SCENE_GAME, game_state        # mid-fight -> ignore
    je   .read_key
    movq $SCENE_HOME, game_state        # guide / credits -> back to the menu
    jmp  .read_key

.start_round:
    call reset_round                    # physics.s: new positions, spears, rain
    movq $SCENE_GAME, game_state        # main.s will now run the game
    jmp  .read_key

.guide:
    cmpq $SCENE_HOME, game_state        # only works from the menu,
    jne  .read_key                      # otherwise 'g' is just ignored
    movq $SCENE_GUIDE, game_state
    jmp  .read_key

.credits:
    cmpq $SCENE_HOME, game_state        # same, only from the menu
    jne  .read_key
    movq $SCENE_CREDITS, game_state
    jmp  .read_key

.quit:
    movq $1, quit_flag                  # main.s sees this and calls endwin
    jmp  .read_key

.no_more_keys:
    # epilogue
    addq $8, %rsp               # undo the alignment padding
    popq %rbx                   # give the caller its rbx back
    movq %rbp, %rsp             # drop our stack frame
    popq %rbp                   # restore the caller's base pointer
    ret                         # back to main.s
