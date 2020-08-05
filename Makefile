CC = gcc

ieeefp_main: ieeefp_main.c ieeefp.o
	$(CC) -no-pie -fno-pie -o ieeefp_main ieeefp_main.c ieeefp.o

ieeefp.o: ieeefp.asm
	nasm -f elf64 ieeefp.asm

all: ieeefp_main

clean:
	rm -f *.o ieeefp_main
