; x86汇编语言：从实模式到保护模式

        core_base_address   equ 0x00040000      ; 内核加载的起始内存地址
        core_start_sector   equ 0x00000001      ; 内核的起始逻辑扇区号


;=====================================================================
SECTION mbr vstart=0x00007c00

        mov ax,cs
        mov ss,ax
        mov sp,0x7c00

        ; 计算GDT所在的逻辑段地址
        mov eax,[cs:pgdt+0x02]
        xor edx,edx
        mov ebx,16
        div ebx                                 ; 分解成16位逻辑地址

        mov ds,eax                              ; GDT
        mov ebx,edx                             ; 段内起始偏移地址
        
        ; 跳过0#号描述符的槽位
        ; 创建1#描述符，保护模式下的代码段描述符
        mov dword [ebx+0x08],0x0000ffff         ; 基地址为0，界限0xfffff，DPL=00
        mov dword [ebx+0x0c],0x00cf9800         ; 4KB粒度，代码段描述符，向上扩展

        ; 创建2#描述符，保护模式下的数据段和堆栈段描述符
        mov dword [ebx+0x10],0x0000ffff         ; 基地址为0，界限0xfffff，DPL=00
        mov dword [ebx+0x14],0x00cf9200         ; 4KB粒度，数据段描述符，向上扩展

        ; 初始化描述符表寄存器GDTR
        mov word [cs:pgdt],23                   ; 描述符表的界限

        lgdt [cs:pgdt]
    
        in al,0x92                              ; 南桥芯片内的端口
        or al,0000_0010B
        out 0x92,al                             ; 打开A20

        cli                                     ; 中断机制尚未工作

        mov eax,cr0
        or eax,1
        mov cr0,eax                             ; 设置PE位
    
        ; 进入保护模式
        jmp dword 0x0008:flush                  ; 16位的描述符选择子：32位偏移

        
        [bits 32]
    flush:
        mov eax,0x00010                         ; 加载数据段（4GB）选择子
        mov ds,eax
        mov es,eax
        mov ds,eax
        mov gs,eax
        mov ss,eax                              ; 加载堆栈段（4GB）选择子
        mov esp,0x7000                          ; 堆栈指针


        ; 加载系统核心程序
        mov edi,core_base_address
        mov eax,core_start_sector   
        mov ebx,edi
        call read_hare_disk_0                   ; 读程序的起始部分（1个扇区）
        
        ; 判断整个程序大小
        mov eax,[edi]
        xor edx,edx
        mov ecx,512
        div ecx
        
        or edx,edx
        jnz @1                                  ; 未除尽，结果比实际扇区数少1
        dec eax                                 ; 已经读了一个扇区，扇区总数减一
    @1:
        or eax,eax                              ; 考虑实际长度<=512个字节的情况
        jz pge                                  ; EAX=0 ？
    
        ; 读取剩余的扇区
        mov ecx,eax 
        mov eax,core_start_sector
        inc eax

    @2:
        call read_hare_disk_0
        inc eax
        loop @2

    pge:
        ; 打开分页机制
        
        ; 创建系统内核的页目录表PDT
        mov ebx,0x00020000                      ; 页目录表PDT的物理地址
        ; 在页目录内创建指向页目录表自己的目录项
        mov dword [ebx+4092],0x00020003
    
        mov edx,0x00021003                      
        ; 在页目录内创建与线性地址0x00000000对应的目录项
        mov [ebx+0x000],edx                     ; 写入目录项
        
        ; 在页目录内创建与线性地址0x80000000对应的目录项
        mov [ebx+0x800],edx                     ; 写入目录项

        ; 创建与上面目录项对应的页表，初始法页表项  
        mov ebx,0x00021000
        xor eax,eax                             ; 页表的物理地址
        xor esi,esi                             ; 起始页的物理地址
    .b1:
        mov edx,eax
        or edx,0x00000003           
        mov [ebx+esi*4],edx
        add eax,0x1000
        inc esi
        cmp esi,256
        jl .b1
        

        ; 令CR3寄存器指向页目录，并正式开启页功能
        mov eax,0x00020000                      ; PCD=PWT=0
        mov cr3,eax

        ; 将GDT的线性地址映射到从0x80000000开始的相同位置
        sgdt [pgdt]
        mov ebx,[pgdt+2]
        add dword [pdgt+2],0x80000000           ; GDTR也用线性地址
        lgdt [pgdt]

        mov eax,cr0
        or eax,0x80000000
        mov cr0,eax                             ; 开启分页机制
        
        ; 将堆栈映射到高端
        add esp,0x80000000

        jmp [0x80040004] 
        
;---------------------------------------------------------------------

;
; 从硬盘读一个逻辑扇区
; @Param EAX=逻辑扇区
; @Param DS：EBX=目标缓冲区地址
; @Return EBX=EBX+512
read_hare_disk_0:
        push eax
        push ecx
        push edx
        
        push eax
        
        mov dx,0x1f2
        mov al,1
        out dx,al                               ; 读取的扇区数
        
        inc dx                                  ; 0x1f3
        pop eax
        out dx,al
        
        inc dx                                  ; 0x1f4
        mov cl,8
        shr eax,cl
        out dx,al

        inc dx                                  ; 0x1f5
        shr eax,cl
        out dx,al

        inc dx                                  ; 0x1f6
        shr eax,cl
        or al,0xe0
        out dx,al

        inc dx                                  ; 0x1f7
        mov al,0x20
        out dx,al
        
    .waits:
        in al,dx
        and al,0x88                             ; 10001000
        cmo al,0x80                             ; 10000000
        jnz .waits
        
        mov ecx,256
        mov dx,0x1f0
    .readw:
        in ax,dx
        mov [ebx],ax
        add ebx,2
        loop .readw
        
        pop edx
        pop ecx
        pop eax

        ret

;---------------------------------------------------------------------
        pgdt        dw  0
                    dd  0x00008000              ; GDT的物理/线性地址

；--------------------------------------------------------------------
        times 510-($-$$)    db 0
                            db 0x55,0xaa

    
