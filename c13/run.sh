# nasm to bin
nasm c13_mbr.asm -o mbr.bin

nasm c13_core.asm -o core.bin

nasm c13.asm -o c.bin


# dd to a.img
dd if=mbr.bin of=a.img bs=512 count=1 conv=notrunc

dd if=core.bin of=a.img bs=512 count=10 seek=1 conv=notrunc

dd if=c.bin of=a.img bs=512 count=10 seek=50 conv=notrunc

