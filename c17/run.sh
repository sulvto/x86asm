#!/bin/bash

# nasm to bin
nasm -f bin c17_mbr.asm -o mbr.bin

nasm -f bin c17_core.asm -o core.bin

nasm -f bin c17_1.asm -o c1.bin

nasm -f bin c17_2.asm -o c2.bin


# dd to a.img
dd if=mbr.bin of=../c.img bs=512 conv=notrunc

dd if=core.bin of=../c.img bs=512 seek=1 conv=notrunc

dd if=c1.bin of=../c.img bs=512 seek=50 conv=notrunc

dd if=c2.bin of=../c.img bs=512 seek=100 conv=notrunc

# run bochs
bochs -q -f .bochsrc
