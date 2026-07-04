.section .text

.globl _start
_start:
    call main
    j _exit

.globl _exit
_exit:
    li a7, 93
    ecall
