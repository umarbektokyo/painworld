# text.s - draw_lines, used by the menu screens

    .text
    .globl draw_lines

# void draw_lines(char **lines, long count, long row, long col)
#                  %rdi           %rsi        %rdx      %rcx
# lines = table of string addresses (.quad str0, str1, ...)
# does mvaddstr(row + i, col, lines[i]) for each line
draw_lines:
    # prologue
    pushq %rbp
    movq  %rsp, %rbp

    # callee-conventions
    pushq %rbx                  # current table entry
    pushq %r12                  # lines left
    pushq %r13                  # row
    pushq %r14                  # col

    movq %rdi, %rbx
    movq %rsi, %r12
    movq %rdx, %r13
    movq %rcx, %r14

.dl_loop:
    cmpq $0, %r12
    je   .dl_done

    movq %r13, %rdi             # mvaddstr(row: row, col: col, str: lines[i])
    movq %r14, %rsi
    movq (%rbx), %rdx           # string address from the table
    call mvaddstr

    addq $8, %rbx               # next entry, addresses are 8 bytes
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
