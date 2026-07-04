PREFIX ?= riscv-none-elf-
ARCH = -march=rv32im_zicsr_zve32x -mabi=ilp32
LINKER_SCRIPT = linker.ld

DEBUG_CFLAGS = -g
CFLAGS = -c -march=rv32im_zicsr_zve32x -mabi=ilp32
LDFLAGS = -T
EXEC = vector_arith.elf

CC = $(PREFIX)gcc
AS = $(PREFIX)as
LD = $(PREFIX)ld
OBJDUMP = $(PREFIX)objdump

deps = main.o start.o vecops.o

all:
	$(CC) $(DEBUG_CFLAGS) $(CFLAGS) main.c
	$(AS) $(DEBUG_CFLAGS) $(ARCH) start.S -o start.o
	$(AS) $(DEBUG_CFLAGS) $(ARCH) vecops.S -o vecops.o
	$(LD) $(LDFLAGS) $(LINKER_SCRIPT) -o $(EXEC) $(deps)

dump:
	$(OBJDUMP) -Ds $(EXEC) | less

clean:
	rm -f $(EXEC) $(deps)
