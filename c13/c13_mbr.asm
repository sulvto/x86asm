;
; x86汇编语言：从实模式到保护模式
; 主引导扇区程序
;

core_base_address equ 0x00040000    ; 内核加载的起始内存地址
core_start_sector equ 0x00000001    ; 内核的起始逻辑扇区号

    mov ax,cs
    mov ss,ax
    mov sp,0x7c00
    
    ; 计算GDT所在的逻辑段地址
    mov eax,[cs:pgdt+0x7c00+0x02]
    xor edx,edx
    mov ebx,16
    div ebx
    
    mov ds,eax      ; 令DS指向该段以进行操作
    mov ebx,edx     ; 段内起始偏移地址
    
    ; 跳过0#号描述符的槽位
    ; 创建1#描述符，这是一个数据段，对应0～4G的线性地址空间
    ; 1111111111111111 110011111001001000000000
    ; 1111111111111111 1 1 0 0 1111 1 00 1 0010 00000000
    mov dword [ebx+0x08], 0x0000ffff    ; 基地址为0，段界限为0xFFFFF
    mov dword [ebx+0x0c], 0x00cf9200    ; 粒度为4KB，存储器段描述符
    
    ; 创建保护模式下初始代码段描述符 
    ; 1111100000000000000000111111111 10000001001100000000000
    ; 111110000000000 0000000111111111 1 0 0 0000 1 00 1 1000 00000000
    mov dword [ebx+0x10], 0x7c0001ff    ; 基地址为0x00007c00，段界限为0x1FF0
    mov dword [ebx+0x14], 0x00409800    ; 粒度为1byte，代码段描述符
    
    ; 创建保护模式下堆栈段描述符
    ; 1111100000000001111111111111110 110011111001011000000000
    ; 111110000000000 1111111111111110 1 1 0 0 1111 1 00 1 0110 00000000
    ; 段界限： 1111 1111111111111110
    mov dword [ebx+0x18], 0x7c00fffe    ; 基地址为0x00007c00，段界限为0xFFFE
    mov dword [ebx+0x1c], 0x00cf9600    ; 粒度为4KB，存储器段描述符
    
    ; 创建保护模式下显示缓冲区描述符
    ; 10000000000000000111111111111111 10000001001001000001011
    ; 1000000000000000 0111111111111111 1 0 0 0000 1 00 1 0010 00001011
    ; 基地址： 10111000000000000000
    mov dword [ebx+0x20], 0x80007fff    ; 基地址为0x000b8000，段界限为0x07FFF
    mov dword [ebx+0x24], 0x0040920b    ; 粒度为字节
    
    ;
    ;      |------------------------------------------|
    ;      |  文本模式显存（000B8000～000BFFFF）      | 0x20
    ; +20  |------------------------------------------|
    ;      |  初始化栈段  （00006C00～00007C00）      | 0x18
    ; +18  |------------------------------------------|
    ;      |  初始化代码段（00007C00～00007DFF）      | 0x10
    ; +10  |------------------------------------------|
    ;      |  0～4G数据段 （00000000～FFFFFFFF）      | 0x08
    ; +08  |------------------------------------------|
    ;      |                空描述符                  | 0x00
    ; +00  |------------------------------------------|
    ; 
    ;                     创建的描述符
    ;

    ; 初始化描述符表寄存器GDTR
    mov word [cs:pgdt+0x7c00],39        ; 描述符表的界限
    
    lgdt [cs: pgdt+0x7c00]
    
    in al,0x92
    or al,0000_0010B
    out 0x92,al
    
    cli
    
    mov eax,cr0
    or eax,1
    mov cr0,eax                         ; 设置PE为
    
    jmp dword 0x0010:flush              ; 16位的描述符选择子：32位偏移

[bits 32]
flush:
    mov eax,0x0008                      ; 加载数据段（0～4G）选择子
    mov ds,eax

    mov eax,0x0018                      ; 加载堆栈段选择子
    mov ss,eax
    xor esp,esp
    
    ; 加载系统核心程序
    mov edi,core_base_address
    mov eax,core_start_sector
    mov ebx,edi
    call read_hard_disk_0
    
    ; 判断整个程序有多大
    mov eax,[edi]                       ; 核心程序尺寸
    xor edx,edx
    mov ecx,512                         ; 512字节每扇区
    div ecx
   
    or edx,edx                          ; or指令会影响 ZF 标志位
    jnz @1                              ; edx 为0 -> zf 为1（真）-> jzn 不转移， 否则反之
    dec eax                             ; 扇区总数减1
@1:
    or eax,eax
    jz setup                            ; eax=0 ?
        
    ; 读剩余的扇区
    mov ecx,eax                         ; 32位 LOOP
    mov eax,core_start_sector
    inc eax                             ; 从下一个逻辑扇区接着读
@2:
    call read_hard_disk_0
    inc eax
    loop @2                             ; 循环读完整个内核

setup:
    mov esi,[0x7c00+pgdt+0x02]          ; 不能在代码段内寻址pgdt，
                                        ; 但可以通过4GB的段来访问
    ; 建立公用例程段描述符
    mov eax,[edi+0x04]                  ; 公用例程代码段起始汇编地址
    mov ebx,[edi+0x08]                  ; 核心数据段汇编地址
    sub ebx,eax
    dec ebx                             ; 公用例程段界限
    add eax,edi                         ; 公用例程段基地址
    mov ecx,0x00409800                  ; 字节粒度的代码段描述符
    call make_gdt_descriptor
    mov [esi+0x28],eax
    mov [esi+0x2c],edx

    ; 建立核心数据段描述符
    mov eax,[edi+0x08]                  ; 核心数据段起始汇编地址 
    mov ebx,[edi+0x0c]                  ; 核心代码段汇编地址
    sub ebx,eax
    dec ebx                             ; 核心数据段界限
    add eax,edi                         ; 核心数据段基地址
    mov ecx,0x00409200                  ; 字节粒度的数据段描述符
    call make_gdt_descriptor
    mov [esi+0x30],eax
    mov [esi+0x34],edx

    ; 建立核心代码段描述符
    mov eax,[edi+0x0c]                  ; 核心代码段起始汇编地址
    mov ebx,[edi+0x00]                  ; 程序总长度
    sub ebx,eax
    dec ebx                             ; 核心代码段界限
    add eax,edi                         ; 核心代码段基地址
    mov ecx,0x00409800                  ; 字节粒度的代码段描述符
    call make_gdt_descriptor
    mov [esi+0x38],eax
    mov [esi+0x3c],edx

    mov word [0x7c00+pgdt],63           ; 描述符表的界限

    lgdt [0x7c00+pgdt]
    
    jmp far [edi+0x10]


;-------------------------------------------------------------------
;
; 从硬盘读取一个逻辑扇区
;   @Param EAX 逻辑扇区号
;   @Param DS:EAX 目标缓冲区地址
;   @Return EBX EBX+512

read_hard_disk_0:
        push eax
        push ecx
        push edx
        
        push eax
        mov dx,0x1f2                        ;   
        mov al,1
        out dx,al                           ; 读取的扇区数
        
        inc dx                              ; 0x1f3
        pop eax
        out dx,al                           ; LBA地址7～0
        
        inc dx                              ; 0x1f4
        mov cl,8
        shr eax,cl
        out dx,al                           ; LBA地址15～8
        
        inc dx                              ; 0x1f5
        shr eax,cl
        out dx,al                           ; LBA地址23～16
    
        inc dx                              ; 0x1f6
        shr eax,cl  
        or al,0xe0                          ; 第一硬盘 LBA地址27～24
        out dx,al           
        
        inc dx                              ; 0x1f7
        mov al,0x20
        out dx,al                           ; 读命令

    .waits:
        in al,dx
        and al,0x88
        cmp al,0x08
        jnz .waits                          ; 不忙，且硬盘已准备好数据传输
        
        mov ecx,256                         ; 总共要读取的字数
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


;------------------------------------------------------------
;
; 构造描述符
;   @Param EAX 线性基地址
;   @Param EBX 段界限
;   @Param ECX 属性（各属性位都在原始位置，其他没用到的位置为0）
;   @Return EDX:EAX 完整的描述符
;
;------------------------------------------------------------
make_gdt_descriptor:
    mov edx,eax
    shl eax,16
    or ax,bx                            ; 描述符前32位（EAX）构造完成
        
    and edx,0xffff0000                  ; 清除基地址中无关的位
    rol edx,8
    bswap edx                           ; 装配基址的31～24和23～16
    
    xor bx,bx
    or edx,edx                          ; 装配段界限的高4位
    
    or edx,ecx                          ; 装配属性
    
    ret


    pgdt        dw 0
                dd 0x00007e00           ; GDT的物理地址
    times 510-($-$$) db 0
                     db 0x55,0xaa
