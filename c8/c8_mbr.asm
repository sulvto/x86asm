; x86汇编语言：从实模式到保护模式

;=====================================================================
app_lba_start equ 100                   ; 常数（用户程序起始扇区号）
                                        ; 常数的声明不会占用汇编地址

SECTION mbr align=16 vstart=0x7c00

        ; 堆栈段和栈指针
        mov ax,0
        mov ss,ax
        mov sp,ax
        
        mov ax,[cs:phy_base]            ; 计算用于加载用户程序的逻辑段地址 
        mov dx,[cs:phy_base+0x02]            
        mov bx,16
        div bx
        mov ds,ax
        mov es,ax

        ; 读取程序的起始部分            ;
        xor di,di
        mov si,app_lba_start
        xor bx,bx                       ; 加载到DS:0x0000处
        call read_hard_disk_0

        ; 判断整个程序有多大
        mov dx,[2]
        mov ax,[0]
        mov bx,512                      ; 除以512
        div bx
        cmp dx,0
        jnz @1                          ; 未除尽，
        dec ax                          ; 除尽，总扇区数减一
    @1:
        cmp ax,0                        ; 考虑实际长度小于等于512个字节的情况
        jz direct

        ; 读取剩余的扇区
        push ds

        mov cx,ax                       ; 循环次数（剩余扇区数）
    @2:
        mov ax,ds
        add,0x20                        ; 512 十六进制的0x20，右移4位后是0x20
        mov ds,ax                       ; 得到下一个以512字节为边界的段地址
        
        xor bx,bx                       ; 每次读时，偏移地址始终为0x0000
        inc si                          ; 下一个逻辑扇区
        call read_hard_disk_0
        loop @2
            
        pop ds                          ; 恢复数据段基址到用户程序头部段
    ; 计算入口点代码段基址
    ; @see 用户程序头部段
    direct:
        mov dx,[0x08]
        mov ax,[0x06]
        call calc_seg_base
        mov [0x06],ax                   ; 回填修正后的入口点代码段基址

        ; 开始处理段重定位表
        mov cx,[0x0a]                   ; 需要重定位的项目数量
        mov bx,0x0c                     ; 重定位表首地址

    realloc:
        mov dx,[bx+0x02]                ; 32位地址的高16位
        mov ax,[bx]
        call calc_seg_base
        mov [bx],ax                     ; 回填段的基址
        add bx,4                        ; 
        loop realloc

        jmp far [0x04]                  ; 转移到用户程序

;---------------------------------------------------------------------
;
; LBA28  从硬盘读取一个扇区
; @Param DI,SI 起始逻辑扇区号. 低16位在SI中，高12位在DI中.
; @Param DS:BX 目标缓冲区地址    
;
read_hard_disk_0:
        push ax
        push bx
        push cx
        push dx

        mov dx,0x1f2
        mov al,1
        out dx,al                           ; 要读的扇区数

        inc dx                              ; 0x1f3
        mov ax,si
        out dx,al                           ; LBA地址 7～0

        inc dx                              ; 0x1f4
        mov al,ah
        out dx,al                           ; LBA地址 15～8

        inc dx                              ; 0x1f5
        mov ax,di
        out dx,al                           ; LBA地址 23～16
        
        inc dx                              ; 0x1f6
        mov al,0xe0                         ; LBA模式，主盘
        or al,ah                            ; LBA地址27～24
        out dx,al
        
        inc dx                              ; 0x1f7
        mov al,0x20                         ; 读命令
        out dx,al

    .waits:
        in al,dx
        and al,0x88                         ; 0x88 -> 10001000
        cmp al,0x08                         ; 0x08 -> 00001000
        jnz .waits                          ; 不忙，且硬盘以准备好数据传输
            
        mov cx,256                          ; 要读的字数
        mov dx,0x1f0

    .readw:
        in ax,dx
        mov [bx],ax                         ; [ds:bx]
        add bx,2
        loop .readw

        pop dx
        pop cx
        pop bx
        pop ax
        
        ret

;---------------------------------------------------------------------
;
; @Param DX:AX 32位的物理地址。高字，低字分别传送到DX，AX
; @Reruen AX 16位逻辑段地址
;
calc_seg_base:
        push dx

        add ax,[cs:phy_base]
        adc dx,[cs:phy_base+0x02]
        shr ax,4
        ror dx,4
        and dx,0xf000
        or ax,dx
        
        pop dx
        
        ret

;---------------------------------------------------------------------

        phy_base dd 0x10000             ; 用户程序被加载的物理起始地址

times 510-($-$$) db 0
                 db 0x55,0xaa
