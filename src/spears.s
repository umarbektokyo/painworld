# spear spawn, pick up, throw, fly, stick, kill
#
# a spear is always in one of 3 states:
#   STUCK   upright in a platform, walk onto it to grab it
#   HELD    follows the owner's head, points where they face
#   FLYING  thrown, flies in a flat arc until it hits a platform (then STUCK)
#           or the other slugcat (then round over)

    .include "constants.inc"

    .text
    .globl spawn_spears
    .globl grab_or_throw
    .globl update_spears
    .globl draw_spears

# void spawn_spears(void)
# each spear goes to a random platform at a random x (16 away from the edges)
spawn_spears:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                                  # amount of spears is saved in rbx
    pushq %r12                                  # platform is saved in r12

    movq $0, %rbx                               # amount of spears is set at 0
.ss_loop:
    cmpq $NUM_SPEARS, %rbx                      # if the amount of placed spears is greater or equal than. 6, jump to .ss_done (stop generating spears)
    jge  .ss_done

    call rand                                   # call the C function rand, generates a random int
    movl %eax, %eax                             # no-op, offers some padding
    movq $0, %rdx                               # empty rdx to put the randomly generated number into it
    movq $NUM_PLATS, %rcx
    divq %rcx                                   # divide NUM_PLATS by rax and save it in rax
    movq %rdx, %r12                             # store the random int in r12, the platform

    call rand                                   # generate another random int
    movl %eax, %eax
    movq plat_x1(,%r12,8), %rcx
    subq plat_x0(,%r12,8), %rcx                 # get the width of the platform (furthest x-coordinate of the platform minus the closest x-coordinate)
    subq $32, %rcx                              # minus 16 on each side of the platform, so it doesn't fall right on the edge
    movq $0, %rdx
    divq %rcx                                   # rdx = random int / width - 32
    addq plat_x0(,%r12,8), %rdx                 # rdx + leftmost edge
    addq $16, %rdx                              # + the 16 bit margin
    movq %rdx, spear_x(,%rbx,8)                 # set this calculated point as the x-coordiniate of the spear

    movq plat_y0(,%r12,8), %rax                 # move the location of the top of the platform to rax
    movq %rax, spear_y(,%rbx,8)                 # make rax the y-coordinate of the spear
    movq $0, spear_vx(,%rbx,8)                  # spear velocity (x and y) is 0, so it is not moving
    movq $0, spear_vy(,%rbx,8)
    movq $SPEAR_STUCK, spear_state(,%rbx,8)     # spear stuck in the ground, thus grabbable

    incq %rbx                                   # add one spear, and jump back to the loop
    jmp  .ss_loop

.ss_done:
    # epilogue
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

# void grab_or_throw(long p /* %rdi */)
# holding one -> throw it. empty hands -> grab a STUCK spear close to our body.
grab_or_throw:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    movq held_spear(,%rdi,8), %rcx              # rcx has whether we have a spear or not (-1 = no spear)
    cmpq $0, %rcx
    jl   .gt_find                               # if we don't have a spear, jump to .gt_find (try to find a spear)
    # throw
    movq $SPEAR_FLYING, spear_state(,%rcx,8)    #state of the spear is flying
    movq move_dir(,%rdi,8), %rax                # rax has the direction we are facing (1 = front, -1 = back)
    movq %rax, spear_dir(,%rcx,8)               # spear points towards where we are facing
    imulq $SPEAR_SPEED, %rax                    # direction * speed = the speed of the throw, which is saved in rax and then spear_vx
    movq %rax, spear_vx(,%rcx,8)                # speed is either 56 or -56 (depending on direction), so the spear flies fast and flat
    movq $-SPEAR_LIFT, spear_vy(,%rcx,8)        # spear flies a bit upwards
    movq $-1, held_spear(,%rdi,8)               # spear was thrown, so you lose the spear
    jmp  .gt_done                               # move on

.gt_find:
    movq %rdi, %r8
    shlq $1, %r8
    incq %r8                                    # body chunk = p * 2 + 1 (the body is at the feet)

    movq $0, %rcx                               # currently holding no spears
.gt_loop:
    cmpq $NUM_SPEARS, %rcx                      # compare the amount of available spears to the amount of spears held
    jge  .gt_done                               # greater or equal? Then don't do anything

    cmpq $SPEAR_STUCK, spear_state(,%rcx,8)     # compare the state of a spear with the value of the spear being stuck
    jne  .gt_next                               # if it's not equal, go to the next spear and compare (flying spears cannot be grabbed)

    movq spear_x(,%rcx,8), %rax                 # |spear x - body x| < GRAB_RANGE_X
    subq chunk_x(,%r8,8), %rax                  # subtract the x coordinate of the spear with that of the body
    cmpq $0, %rax                               # compare this distance with 0
    jge  .gt_abs_x                              # if it's greater or equal to 0, jump to .gt_abs_x (see if we're whithin horizontal range)
    negq %rax                                   # if the code got here, then the value is negative, so we flip it, taking the absolute value
.gt_abs_x:
    cmpq $GRAB_RANGE_X, %rax                    # is the horizontal distance from the spear greater or equal than the range? Go to the next spear
    jge  .gt_next

    movq spear_y(,%rcx,8), %rax                 # this (from line 110 until 117) is the same we just did, but with the vertical distance
    subq chunk_y(,%r8,8), %rax
    cmpq $0, %rax
    jge  .gt_abs_y
    negq %rax
.gt_abs_y:
    cmpq $GRAB_RANGE_Y, %rax                    
    jge  .gt_next

    movq $SPEAR_HELD, spear_state(,%rcx,8)      # you're close enough to a spear, so it gets picked up
    movq %rdi, spear_owner(,%rcx,8)             # we now hold a spear
    movq %rcx, held_spear(,%rdi,8)              # remember which spear we hold
    jmp  .gt_done

.gt_next:
    incq %rcx                                   # next spear
    jmp  .gt_loop

.gt_done:
    # epilogue
    movq %rbp, %rsp
    popq %rbp
    ret

# void update_spears(void)
#   HELD:   copy the owner's head position + facing
#   FLYING: gravity, move, edges, stick into platforms, hit the other player
update_spears:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                                  # spear
    subq  $8, %rsp                              # stack aligned

    movq $0, %rbx                               # spear s = 0
.us_loop:
    cmpq $NUM_SPEARS, %rbx                      # compare the amount of spears with the max amount of spears (6), if it's greater or equal then jump to .us_done(end)
    jge  .us_done

    cmpq $SPEAR_HELD, spear_state(,%rbx,8)      # if the spear is being held, jump to .us_held
    je   .us_held
    cmpq $SPEAR_FLYING, spear_state(,%rbx,8)    # if the spear is flying, jump to .us_flying
    je   .us_flying
    jmp  .us_next                               # otherwise (spear is stuck), move to the next spear

.us_held:
    movq spear_owner(,%rbx,8), %rax             # rax has the value of who holds the spear
    movq move_dir(,%rax,8), %rcx                # rcx has the direction the player is facing
    movq %rcx, spear_dir(,%rbx,8)               # spear points where player is facing
    shlq $1, %rax                               # multiply rax by 2 (focusing on the head chunk of the player)
    movq chunk_x(,%rax,8), %rcx                 # x and y coordinate of the spear is allocated to the coordinates of the head chunk (line 162 - 166)
    movq %rcx, spear_x(,%rbx,8) 
    movq chunk_y(,%rax,8), %rcx
    movq %rcx, spear_y(,%rbx,8)
    jmp  .us_next                               # go to the next spear

.us_flying:
    addq $SPEAR_GRAVITY, spear_vy(,%rbx,8)      # add the gravity of its spear to the vertical speed
    cmpq $SPEAR_MAX_FALL, spear_vy(,%rbx,8)     # if the max a spear can fall is less or equal than the vertical speed, jump to .us_no_cap
    jle  .us_no_cap
    movq $SPEAR_MAX_FALL, spear_vy(,%rbx,8)     # otherwise, copy the max fall to the vertical speed
.us_no_cap:                                     # MAX_FALL is lower than the thickness of one platform so it cannot fall through

    movq spear_vx(,%rbx,8), %rax                # change in horizontal velocity, basically x = x + vx
    addq %rax, spear_x(,%rbx,8)
    movq spear_vy(,%rbx,8), %rax                # change in vertical velocity, basically y = y + vy
    addq %rax, spear_y(,%rbx,8)

    cmpq $0, spear_x(,%rbx,8)                   # if the horizontal coordinate of the spear is greater or equal than 0, jump to .us_right
    jge  .us_right
    movq $0, spear_x(,%rbx,8)                   # else, the spear hit a wall so the position is 0, and the velocity is 0 (it drops)
    movq $0, spear_vx(,%rbx,8)
.us_right:
    cmpq $WORLD_W - 1, spear_x(,%rbx,8)         # if the x coordinate of the spear is less or equal to the width of the screen - 1, jump to .us_edges_done
    jle  .us_edges_done
    movq $WORLD_W - 1, spear_x(,%rbx,8)         # else, set it to be that way, and cut the velocity
    movq $0, spear_vx(,%rbx,8)
.us_edges_done:

    movq spear_x(,%rbx,8), %rdi                 # x and y coordinates of the spear saved in rdi and rsi respectively
    movq spear_y(,%rbx,8), %rsi 

    cmpq $0, spear_vy(,%rbx,8)                  # if the vertical celocity of the spear is less than 0, jump to .us_players
    jl   .us_players
    call find_platform                          # call the find_platform from render.s, and store the platform value to rax
    cmpq $0, %rax                               # if the platform value is lower than 0 (spear is in the air), jump to .us_players 
    jl   .us_players            

    movq plat_y0(,%rax,8), %rcx                 # store the location of the top of the platform into rcx and then into the y value of the spear
    movq %rcx, spear_y(,%rbx,8)
    movq $0, spear_vx(,%rbx,8)                  # stop the spear (vtot = 0)
    movq $0, spear_vy(,%rbx,8)
    movq $SPEAR_STUCK, spear_state(,%rbx,8)     # make the spear be stuck so it can be picked up and jump to the next spear
    jmp  .us_next

.us_players:
    movq $0, %rcx                               # check if the spear hits
.us_hit_loop:
    cmpq $NUM_CHUNKS, %rcx                      # compare the checked chunks with the total amount of chunks
    jge  .us_next                               # if it's greater or equal, jump to the next spear

    movq %rcx, %rax
    shrq $1, %rax                               # rax holds the value of the player being checked
    cmpq spear_owner(,%rbx,8), %rax
    je   .us_next_chunk                         # if the player being checked is the spear owner, jump to the next chunck (cannot hurt yourself)

    # check if the player (circle) got hit (formula for a circle: xˆ2 + yˆ2 = rˆ2)
    movq %rdi, %r8                              # get the x coordinate of the spear in r8
    subq chunk_x(,%rcx,8), %r8                  # subtract the x coordinate of the chunk to r8 (difference in x)
    imulq %r8, %r8                              # square dx
    movq %rsi, %r9                              # same process we did for x, but vertically and load the dyˆ2 in r9
    subq chunk_y(,%rcx,8), %r9  
    imulq %r9, %r9              
    addq %r9, %r8                               # add dxˆ2 and dyˆ2
    movq chunk_r(,%rcx,8), %r10                 # move r into r10 and square it
    imulq %r10, %r10            
    cmpq %r10, %r8                              # if, effectively, dxˆ2 + dyˆ2 = rˆ2, then the spear hit, so if it's greater, then it missed and should go to the next chunk
    jge  .us_next_chunk         

    movq spear_owner(,%rbx,8), %rax             # the player who thre the spear gets put in rax and crowned winner!
    movq %rax, winner
    incq kills(,%rax,8)                         # increase the kill count (points)
    movq $SCENE_END, game_state                 # end this scene and jump to the next case
    jmp  .us_next

.us_next_chunk:
    incq %rcx                                   # next circle
    jmp  .us_hit_loop

.us_next:
    incq %rbx                                   # next spear
    jmp  .us_loop

.us_done:
    # epilogue
    addq $8, %rsp
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret

# void draw_spears(void)
# plain chars on top of the world (row = y / 32, col = x / 16):
#   STUCK -> 3 '|' going up,  HELD / FLYING -> "---->" or "<----"
# mvaddch just ignores stuff off screen, so no bounds checks
draw_spears:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                                  # spear
    pushq %r12                                  # row
    pushq %r13                                  # col
    pushq %r14                                  # k = amount of times a character is drawn

    movq $0, %rbx                               # spear s = 0
.ds_loop:
    cmpq $NUM_SPEARS, %rbx                      # compare the amount of checked spears with the total amount of spears, if greater or equal, jump to .ds_done
    jge  .ds_done

    movq spear_y(,%rbx,8), %r12                 # copy the y coordinate of the spear in r12 and divide it by 32 to get the screen row
    shrq $5, %r12              
    movq spear_x(,%rbx,8), %r13                 # copy the x coordinate of the spear in r13 and divide it by 16 to get the screen column
    shrq $4, %r13               

    cmpq $SPEAR_STUCK, spear_state(,%rbx,8)     # if the spear is stuck, it looks upright, so if it isn't, it's laying flat, thus it jumps to .ds_flat
    jne  .ds_flat               

    movq $1, %r14                               # start drawing the '|' characters from 1, so move 1 into r14
.ds_up_loop:
    cmpq $3, %r14                               # have three '|' been printed? if more were printed move on to the next spear
    jg   .ds_next
    movq %r12, %rdi                             # move the row value onto rdi
    subq %r14, %rdi                             # subtract k from the rdi
    movq %r13, %rsi                             # copy the column on rsi
    movq $'|', %rdx                             # copy the '|' char onto rdx
    call mvaddch                                # add that character to what is being printed
    incq %r14                                   # next row up
    jmp  .ds_up_loop

.ds_flat:
    movq $-2, %r14                              # want to print '-' from -2 until 2, so move -2 into r14
.ds_flat_loop:
    cmpq $2, %r14                               # if the 5 '-' characters have been drawn, jump to .ds_tip
    jg   .ds_tip
    movq %r12, %rdi                             # the same thing we do for the '|' characters, but we do for '-'
    movq %r13, %rsi
    addq %r14, %rsi
    movq $'-', %rdx
    call mvaddch
    incq %r14                   
    jmp  .ds_flat_loop

.ds_tip:
    movq %r12, %rdi                             # start on the same row as the rows of '-' characters, now in rdi
    cmpq $1, spear_dir(,%rbx,8)                 # if the spear is pointing to the left, jump to .ds_tip_left
    jne  .ds_tip_left
    movq %r13, %rsi                             # overwrite the last '-' character and draw a '>' character in its place
    addq $2, %rsi
    movq $'>', %rdx             
    call mvaddch
    jmp  .ds_next                               # jump to the next spear
.ds_tip_left:
    movq %r13, %rsi                             # the spear is pointing to the left, so it overwrites the first '-' character and replaces it with a '<' character
    subq $2, %rsi
    movq $'<', %rdx             
    call mvaddch

.ds_next:
    incq %rbx                                   # next spear
    jmp  .ds_loop

.ds_done:
    # epilogue
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret
