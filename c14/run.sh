#!/bin/bash

# nasm to bin
nasm ../c13/c13_mbr.asm -o ../c13/mbr.bin

nasm c14_core.asm -o core.bin

nasm ../c13/c13.asm -o ../c13/c.bin


# dd to a.img
dd if=../c13/mbr.bin of=../c.img bs=512 count=1 conv=notrunc

dd if=core.bin of=../c.img bs=512 count=10 seek=1 conv=notrunc

dd if=../c13/c.bin of=../c.img bs=512 count=50 seek=50 conv=notrunc

dd if=../c13/diskdata.txt of=../c.img bs=512 count=10 seek=100 conv=notrunc
# run bochs
bochs -q -f ../.bochsrc
