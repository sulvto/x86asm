#!/bin/bash


# nasm
nasm c8.asm -o c8.bin
nasm c8_mbr.asm -o mbr.bin

dd if=mbr.bin of=../c.img bs=512 count=1 conv=notrunc

dd if=c8.bin of=../c.img bs=512 count=40 seek=100 conv=notrunc

# run bochs
bochs -q -f .bochsrc
