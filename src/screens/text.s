    #=============================================================================
    # painworld — src/screens/text.s
    # Helper for the menu screens: draw a list of strings, one per row.
    #=============================================================================

    .text
    .globl draw_lines

    #-----------------------------------------------------------------------------
    # void draw_lines(char **lines /* %rdi */, long count /* %rsi */,
    #                 long row /* %rdx */, long col /* %rcx */)
    #
    # lines is a table of string addresses (.quad str0, str1, ...).
    #   for i in 0..count-1:  mvaddstr(row + i, col, lines[i])
    #-----------------------------------------------------------------------------
draw_lines:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # rbx = address of the current table entry
    pushq %r12                  # r12 = lines left to draw
    pushq %r13                  # r13 = row
    pushq %r14                  # r14 = col

    movq %rdi, %rbx
    movq %rsi, %r12
    movq %rdx, %r13
    movq %rcx, %r14

.dl_loop:
    cmpq $0, %r12
    je   .dl_done

    movq %r13, %rdi             # mvaddstr(row, col, lines[i])
    movq %r14, %rsi
    movq (%rbx), %rdx           # rdx = the string's address from the table
    call mvaddstr

    addq $8, %rbx               # next table entry (8 bytes per address)
    incq %r13                   # next row
    decq %r12
    jmp  .dl_loop

.dl_done:
    # epilogue
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret
