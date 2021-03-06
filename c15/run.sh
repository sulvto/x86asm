#!/bin/bash

# nasm to bin
nasm ../c13/c13_mbr.asm -o mbr.bin

nasm -f bin c15_core.asm -o core.bin

nasm -f bin c15.asm -o c.bin


# dd to a.img
dd if=mbr.bin of=../c.img bs=512 count=1 conv=notrunc

dd if=core.bin of=../c.img bs=512 count=49 seek=1 conv=notrunc

dd if=c.bin of=../c.img bs=512 count=50 seek=50 conv=notrunc

# run bochs
bochs -q -f .bochsrc
