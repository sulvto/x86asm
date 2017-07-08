; x86汇编语言：从实模式到保护模式

        core_code_seg_sel       equ 0x38        ; 111_0_00 内核代码段选择子
        core_data_seg_sel       equ 0x30        ; 110_0_00 内核数据段选择子
        sys_routine_seg_sel     equ 0x28        ; 101_0_00 系统公共例程代码段选择子
        video_ram_seg_sel       equ 0x20        ; 100_0_00 视频显示缓冲区段选择子
        core_stack_seg_sel      equ 0x18        ; 011_0_00 内核堆栈段选择子
        mem_0_4_gb_seg_sel      equ 0x08        ; 001_0_00 整个0-4GB内存段选择子
    
;---------------------------------------------------------------------

        ; 系统核心的头部，用于加载核心程序
        core_len        dd  core_end                    ; #00
        sys_routine_seg dd  section.sys_routine.start   ; #04
        core_data_seg   dd  section.core_data.start     ; #08
        core_code_seg   dd  section.core_code.start     ; #0c
        core_entey      dd  start                       ; #10
                        dw  core_code_seg_sel

         
;=====================================================================
        [bits 32]
;=====================================================================
SECTION sys_routine vstart=0

;
; 字符串显示
; DS:EBX 串地址
;
put_string:
        push ecx
    .getc:
        mov cl,[ebx]
        or cl,cl
        jz .exit
        call put_char
        inc ebx
        jmp .getc
    .exit
        pop ecx
        retf                        ; 段间返回
    
;---------------------------------------------------------------------
;
; 字符显示
; CL=字符ASCII码
;
put_char:
        pushad
        
        ; 取当前光标位置
        mov dx,0x3d4
        mov al,0x0e
        out dx,al
        inc dx
        in al,dx
        mov ah,al    
    
        dec dx                      ; 0x3d4
        mov al,0x0f
        out dx,al
        inc dx                      ; 0x3d5
        in al,dx
        mov bx,ax
    
        cmp cl,0x0d
        jnz .put_0a
        mov ax,bx
        mov bl,80
        div bl
        mul bl
        mov bx,ax
        jmp .set_cursor

    .put_0a:
        cmp cl,0x0a
        jnz .put_other
        add bx,80
        jmp .roll_screen

    .put_other:
        push es
        mov eax,video_ram_seg_sel
        mov es,eax
        shl bx,1
        mov [es:bx],cl  
        pop es

        ; 推进光标
        shr bx,1
        inc bx

    .roll_screen:
        cmp bx,2000
        jl .set_cursor  
        
        push ds
        push es
        mov eax,video_ram_seg_sel
        mov ds,eax
        mov es,eax
        cld
        mov esi,0xa0
        mov edi,0x00
        mov ecx,1920
        rep movsd
        mov bx,3840
        mov ecx,80
    .cls:
        mov word[es:bx],0x0720
        add bx,2
        loop .cls

        pop es
        pop ds
        
        mov bx,1920

    .set_cursor:
        mov dx,0x3d4
        mov al,0x0e
        out dx,al
        inc dx
        mov al,bh
        out dx,al
        dec dx
        mov al,0x0f
        out dx,al
        inc dx
        mov al,bl
        out dx,al
        
        popad

        ret        

;---------------------------------------------------------------------
; 从硬盘读取一个逻辑扇区
; EAX=逻辑扇区号
; DS：EBX=目标缓冲区地址
; @Retuen EBX=EBX+512
read_hard_disk_0:
        push eax
        push ecx
        push edx
        
        push eax
        mov dx,0x1f2
        mov al,1
        out dx,al
        
        inc dx                      ; 0x1f3
        pop eax
        out dx,al                   ; LBA地址7～0

        inc dx                      ; 0x1f4
        mov cl,8
        shr eax,cl
        out dx,al                   ; LBA地址15～8
        
        inc dx                      ; 0x1f5
        shr eax,cl
        out dx,al                   ; LBA地址23～16
        
        inc dx                      ; 0x1f6
        shr eax,cl
        or al,0xe0  
        out dx,al

        inc dx                      ; 0x1f7
        mov al,0x20                 ; 0x20读命令
        out dx,al                   ; 
           
        ; 端口0x1f7部分状态位的含义
        ;   7   6   5   4   3   2   1   0
        ; ---------------------------------
        ; |BSY|   |   |   |DRQ|   |   |ERR|
        ; ---------------------------------
        ; BSY 为1表示硬盘忙
        ; DRQ 为1表示硬盘已准备好和主机交换数据
        ; ERR 为1表示前一个命令执行错误。具体原因访问端口0x1f1
        ;

    .waits:
        in al,dx
        and al,0x88                 ; 0x88 = 10001000
        cmp al,0x08                 ; 0x08 = 00001000
        jnz .waits                  ; 不忙，且硬盘已准备好数据传输
        
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

        retf

;--------------------------------------------------------------------
;
; 在当前光标处以十六进制形式显示
; @Param EDX=要转换并显示的数字
;
put_hex_dword:
        pushad
        push ds 
        
        mov ax,core_data_seg_sel
        mov ds,ax
    
        mov ebx,bin_hex
        mov ecx,8
    .xlt:
        rol edx,4           
        mov eax,edx
        and eax,0x0000000f
        xlat
        
        push ecx
        mov cl,al
        call put_char
        pop ecx
        
        loop .xlt

        pop ds
        popad

        ret
   
;---------------------------------------------------------------------
; 在GDT内安装一个新的描述符 
; @Param EDX:EAX = 描述符
; @Return CX = 描述符的选择子 
; 
set_up_gdt_descriptor:
        push eax
        push ebx
        push edx

        push ds
        push es

        mov ebx,core_data_seg_sel
        mov ds,ebx

        sgdt [pgdt]                     ; 取出GDT
        
        mov ebx,mem_0_4_gb_seg_sel
        mov es,ebx
        
        movax ebx,word [pgdt]
        inc bx
        add ebx,[pgdt+2]

        mov [es:ebx],eax
        mov [es:ebc+4],edx
        add word [pgdt],8
        
        lgdt [pgdt]

        mov ax,[pgdt]
        or dx,dx
        mov bx,8
        div bx
        mov cx,ax
        shl cx,3

        pop es
        pop ds
        pop edx
        pop eax

        retf
;---------------------------------------------------------------------
; 构造存储器和系统的段描述符
; @Param EAX=线性基地址
; @Param EBX=段界限
; @Param ECX=属性
; @Return EDX：EAX=描述符
make_seg_descriptor:
        mov edx,eax
        shl eax,16
        or ax,bx
        
        and edx,0xffff0000
        rol edx,8
        bswap edx

        xor bx,bx
        or edx,ebx
        
        or edx,ecx
        retf
;---------------------------------------------------------------------
; 构造门的描述符(p259)
; @Param EAX=门代码在段内偏移地址
; @Param BX=门代码所在段的选择子
; @Param CX=段类型及属性
; @Return EDX：EAX=完整的描述符

make_gate_descriptor:
        push ebx
        push ecx

        mov edx,eax
        and edx,0xffff0000
        or dx,cx
        
        and eax,0x0000ffff
        shl ebx,16        
        or eax,ebx

        pop ecx
        pop ebx
        
        retf

;---------------------------------------------------------------------
; 分配一个4KB的页
; @Return EAX=页的物理地址
;
allocate_a_4k_page:
        push ebx
        push ecx
        push edx
        push ds
        
        mov eax,core_data_seg_sel
        mov ds,eax
        
        xor eax,eax
    .b1:
        bts [page_bit_map],eax
        jnc .b2
        inc eax
        cmp eax,page_map_len*8
        ji .b1
    
        ; 没有可以分配的页，停机
        mov ebx,message_3
        call sys_routine_seg_sel:put_string
        hlt                         
        
    .b2:
        shl eax,12              ; 乘以4096（0x1000）

        pop ds
        pop edx
        pop ecx
        pop ebx
        
        ret
;---------------------------------------------------------------------
; 分配一个页，并安装在当前活动的层次分页结构中
; @Param EBX=页的线性地址
; 
alloc_inst_a_page:
        push eax
        push ebx
        push esi
        push ds

        mov eax,mem_0_4_gb_seg_sel
        mov ds,eax
                
        ; 检查该线性地址所对应的页表是否存在
        mov esi,ebx
        ; 1111111111000000 0000000000000000
        and esi,0xffc00000                  ; 保留高10位
        shr esi,20                          ; 得到页目录索引，并乘以4
        or esi,0xfffff000                   ; 页目录自身的线性地址+表内偏移
        
        test dword [esi],0x00000001         ; P位是否为"0".检查该线性
        jnz .b1                             ; 地址是否已经有对应的页表
        
        ; 创建该线性地址所对应的页表
        call allocate_a_4k_page             ; 分配一个页作为页表  
        or eax,0x00000007                   ; 111
        mov [esi],eax        

    .b1:
        ; 开始访问该线性地址所对应的页表
        mov esi,ebx
        shr esi,10

        ; 00000000001111111111000000000000
        and esi,0x003ff000                  ; 或0xfffff000，因高10位是零
        ; 11111111110000000000000000000000
        or esi,0xffc00000                   ; 得到该页表的线性地址
        
        ; 得到该线性地址在页表的对应条目（页表项） 
        ; 11111111110000000000000000000000
        and ebx,0x003ff000
        shr ebx,10                          ; 相当于右移12位，再乘以4
        or esi,ebx                          ; 页表项的线性地址
        call allocate_a_4k_page             ; 分配一个页，这才是需要安装的页
        ; 0...007
        or eax,0x00000007
        mov [esi],eax

        pop ds
        pop esi
        pop ebx
        pop eax
        
        retf

;---------------------------------------------------------------------
; 创建新页目录，并复制当前页目录内容
; @Return EAX=新页目录的物理地址
;
create_copy_cur_pdir:
        push ds
        push es
        push esi
        push edi
        push ebx
        push ecx

        mov ebx,mem_0_4_gb_seg_sel
        mov ds,ebx
        mov es,ebx
        
        call alloc_inst_a_page
        mov ebx,eax
        or ebx,0x00000007
        mov [0xfffffff8],ebx

        mov esi,0xfffff000                  ; ESI 当前页目录的线性地址
        mov edi,0xffffe000                  ; EDI 新页目录的线性地址
        mov ecx,1024                        ; ECX 要复制的目录项数
        cld
        repe movsd

        pop ecx
        pop ebx
        pop edi
        pop esi
        pop es
        pop ds

        retf

;---------------------------------------------------------------------
;
; 终止当前任务
;
terminate_current_task:
        mov eax,core_data_seg_sel
        mov ds,eax
        
        pushfd
        pop edx

        test dx,0100_0000_0000_0000B
        jnz .b1
        jmp far [program_man_tss]
    .b1:
        iretd        

sys_routine_end:

;=====================================================================
SECTION core_data vstart=0
        pgdt            dw  0               ; 用于设置和修改GDT
                        dd  0

        page_bit_map    db  0xff,0xff,0xff,0xff,0xff,0x55,0x55,0xff
                        db  0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                        db  0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                        db  0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                        db  0x55,0x55,0x55,0x55,0x55,0x55,0x55,0x55
                        db  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
                        db  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
                        db  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        page_map_len    equ $-page_bit_map

        ; 符号地址检索表
        salt:
        salt_1          db  '@PringString'
                    times 256-($-salt_1) db 0
                        dd put_string
                        dw sys_routine_seg_sel

        salt_2          db  '@ReadDiskData'
                    times 256-($-salt_2) db 0
                        dd read_hard_disk_0
                        dw sys_routine_seg_sel
    
        salt_3          db  '@PrintDWordAsHexString'
                    times 256-($-salt_3) db 0
                        dd put_hex_dword
                        dw sys_routine_seg_sel

        salt_4          db  '@TerminateProgram'
                    times 256-($-salt_4) db 0
                        dd terminate_current_task
                        dw sys_routine_seg_sel

        salt_item_len   equ $-salt_4
        salt_items      equ ($-salt)/salt_item_len

        message_0       db  '    Working in system core,protect mode.'
                        db  0x0d,0x0a,0

        message_1       db  '   Paging is enabld.System core is mappe'
                        db  'd to address 0x80000000.',0x0d,0x0a,0
                        
        message_2       db  0x0d,0x0a
                        db  '   System wide CALL-GATE mounted.',0x0d,0x0a,0
        message_3       db  '********* No more pages *********'

        message_4       db  0x0d,0x0a,'   Task switching...@_@',0x0d,0x0a,0

        message_5       db  0x0d,0x0a,'   Procesor HALT.',0

        bin_hex         db  '0123456789ABCDEF'   ; put_hex_dword 用的查找表

        core_buf  times 512 db 0                ; 内核用的缓冲区

        cpu_brnd0
        cpu_brand   times 52 db 0       
        cpu_brnd1       db  0x0d,0x0a,0x0d,0x0a,0

        tcb_chain       dd 0                    ; 任务控制块

        ; 内核信息
        core_next_laddr dd  0x80100000          ; 内核空间中下一个可分配的线性地址
        program_man_tss dd  0                   ; 程序管理器的TSS描述符选择子
                        dw  0

core_data_end:

;=====================================================================
SECTION core_code   vstart=0
;
; 在LDT内安装一个新的描述符
; @Param EDX：EAX = 描述符
; @Return CX = 描述符的选择子
;
fill_descriptor_in_ldt:
        push eax
        push edx
        push edi
        push ds
        
        mov ecx,mem_0_4_gb_seg_sel
        mov ds,ecx
        
        mov edi,[ebx+0x0c]                      ; 获得LDT基地址
        
        xor ecx,ecx
        mov cx,[ebx+0x0a]                       ; 获得LDT界限
        inc cx                                  ; LDT的总字节数，即新描述符的偏移地址

        mov [edi+ecx+0x00],eax                  ; 
        mov [edi+ecx+0x04],edx                  ; 安装描述符

        add cx,8            
        dec cx                                  ; 得到新的LDT界限值

        mov [ebx+0x0a],cx                       ; 更新LDT界限值到TCB

        mov ax,cx
        xor dx,dx
        mov cx,8
        div cx

        mov cx,ax
        shl cx,3
        or cx,0000_0000_0000_0100B

        pop ds
        pop edi
        pop edx
        pop eax

        ret

;---------------------------------------------------------------------
; 加载并重定位用户程序
; @Param PUSH 逻辑扇区号
;        PUSH 任务控制块基地址
; 
load_relocate_program:
        pushad
        
        push ds
        push es
        
        mov ebp,esp

        mov ecx,mem_0_4_gb_seg_sel
        mov es,ecx
        
        ; 清空当前页目录的前半部分
        ; 11111111111111111111000000000000
        mov ebx,0xfffff000
        xor esi,esi
    .b1:
        mov dword [es:ebx+esi*4],0x00000000
        inc esi
        cmp esi,512
        jl .b1
        
        ; 分配内存并加载用户程序
        mov eax,core_data_seg_sel
        mov ds,eax
        
        mov eax,[ebp+12*4]                  ;从堆栈取用户程序起始扇区号
        mov ebx,core_buf                    
        call sys_routine_seg_sel:read_hard_disk_0

        mov eax,[core_buf]                  ; 程序尺寸
        mov ebx,eax
        ; 11111111111111111111000000000000
        and ebx,0xfffff000                  ; 4KB对齐
        add ebx,0x1000
        test eax,0x00000fff                 ; 4K的整数倍？（低12位为全是0）
        cmovnz eax,ebx                      ; 不是，使用凑整的结果
        
        mov ecx,eax
        shr ecx,12                          ; 相当于除以4096.程序占用的总4KB页数

        mov eax,mem_0_4_gb_seg_sel
        mov ds,eax
            
        mov eax,[ebp+12*4]
        mov esi,[ebp+11*4]
    .b2:
        mov ebx,[es:esi+0x06]
        add dword [es:esi+0x06],0x1000
        call sys_routine_seg_sel:alloc_inst_a_page
        
        push ecx
        mov ecx,8
    .b3:
        call sys_routine_seg_sel:read_hard_disk_0
        inc eax
        loop .b3
        pop ecx
        loop .b2


        ; 在内核地址空间内创建用户任务的TSS
        mov eax,core_data_seg_sel
        mov ds,eax
        
        mov ebx,[core_next_laddr]           ; 用户任务的TSS必须在全局空间上分配
        call sys_routine_seg_sel:alloc_inst_a_page
        add dword [core_next_laddr],4096

        mov [es:esi+0x14],ebx               ; 在TCB中填写TSS的线性地址
        mov word [es:esi+0x12],103          ; 在TCB中填写TSS的界限值


        ; 在用户任务的局部地址空间内创建LDT
        mov ebx,[es:esi+0x06]               ; 从TCB中取得可用的线性地址
        add dword [es:esi+0x06],0x1000
        call sys_routine_seg_sel:alloc_inst_a_page
        mov [es:esi+0x0c],ebx               ; 填写LDT线性地址到TCB中

        ; 建立程序代码段描述符
        mov eax,0x00000000
        mov ebx,0x000fffff
        ; 110000001111100000000000
        mov ecx,0x00c0f800                  ; 4KB粒度的代码描述符，特权级3
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                         ; TCB的基地址
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B          ;  设置选择子的特权级为3

        mov ebx,[es:esi+0x14]               ; 从TCB中获取TSS的线性地址
        mov [es:ebx+76],cx                  ; 填写TSS的CS域

        ; 建立程序数据段描述符
        mov eax,0x00000000
        mov ebx,0x000fffff
        mov ecx,0x00c0f200                  ; 4KB粒度的数据段描述符，特权级3
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                         ; TCB的基地址
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B
            
        mov ebx,[es:esi+0x14]               ; 从TCB中获取TSS的线性地址
        mov [es:ebx+84],cx                  ; 填写TSS的DS域
        mov [es:ebx+72],cx                  ; 填写TSS的ES域
        mov [es:ebx+88],cx                  ; 填写TSS的FS域
        mov [es:ebx+92],cx                  ; 填写TSS的GS域

        ; 将数据段作为用户任务的3特权级固有堆栈
        mov ebx,[es:esi+0x06]               ; 从TCB中获取可用的线性地址
        add dword [es:esi+0x06],0x100
        call sys_routine_seg_sel:alloc_inst_a_page

        mov ebx,[es:esi+0x14]               ; 从TCB中获取TSS的线性地址
        mov [es:ebx+80],cx                  ; 填写TSS的SS域
        mov edx,[es:esi+0x06]               ; 堆栈的高端线性地址
        mov [es:ebx+56],edx                 ; 填写TSS的ESP域    

        ; 在用户任务的局部地址空间内创建0特权级堆栈
        mov ebx,[es:esi+0x06]               ; 从TCB中获取TSS的线性地址
        add dword [es:esi+0x06],0x1000
        call sys_routine_seg_sel:alloc_inst_a_page
        
        mov eax,0x00000000
        mov ebx,0x000fffff
        mov ecx,0x00c09200
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                         ; TCB的基地址
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0000B
    
        mov ebx,[es:esi+0x14]               ; 从TCB中获取TSS的线性地址
        mov [es:ebx+8],cx                   ; 填写TSS的SS0域
        mov edx,[es:esi+0x06]               ; 堆栈的高端线性地址
        mov [es:ebx+4],ebx                  ; 填写TSS的ESP0域    

        ; 在用户任务的局部地址空间内创建1特权级堆栈
        mov ebx,[es:esi+0x06]               ; 从TCB中获取TSS的线性地址
        add dword [es:esi+0x06],0x1000
        call sys_routine_seg_sel:alloc_inst_a_page
        
        mov eax,0x00000000
        mov ebx,0x000fffff
        mov ecx,0x00c0b200
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                         ; TCB的基地址
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0001B
                                                                       
        mov ebx,[es:esi+0x14]               ; 从TCB中获取TSS的线性地址
        mov [es:ebx+16],cx                   ; 填写TSS的SS1域
        mov edx,[es:esi+0x06]               ; 堆栈的高端线性地址
        mov [es:ebx+12],ebx                  ; 填写TSS的ESP1域    

        ; 在用户任务的局部地址空间内创建2特权级堆栈
        mov ebx,[es:esi+0x06]               ; 从TCB中获取TSS的线性地址
        add dword [es:esi+0x06],0x1000
        call sys_routine_seg_sel:alloc_inst_a_page
        
        mov eax,0x00000000
        mov ebx,0x000fffff
        mov ecx,0x00c0d200
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                         ; TCB的基地址
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0010B
                                                                       
        mov ebx,[es:esi+0x14]               ; 从TCB中获取TSS的线性地址
        mov [es:ebx+24],cx                   ; 填写TSS的SS2域
        mov edx,[es:esi+0x06]               ; 堆栈的高端线性地址
        mov [es:ebx+20],ebx                  ; 填写TSS的ESP2域    


        ; 重定位SALT
        mov eax,mem_0_4_gb_seg_sel
        mov es,eax
        
        mov eax,core_data_seg_sel
        mov ds,eax
        
        cld
    
        mov ecx,[es:0x0c]                   ; U-SALT条目数           
        mov edi,[es:0x08]                   ; U-SALT在4GB空间内的偏移

    .b4:
        push ecx
        push edi

        mov ecx,salt_items
        mov esi,salt
    .b5:
        push edi
        push esi
        push ecx

        mov ecx,64
        repe cmpsd                          ; 每次比较4字节
        jnz .b6
        mov eax,[esi]                       ; 若匹配，则esi恰好指向其后的地址
        mov [es:edi-256],eax                ; 将字符串改写成偏移地址
        mov ax,[esi+4]              
        or ax,0000000000000011B             ; 修改特级权为3

        mov [es:edi-252],ax                 ; 回填调用门选择子

    .b6:
        
        pop ecx
        pop esi
        add esi,salt_item_len               ; 下一个C-SALT
        pop edi
        loop .b5

        pop edi
        add edi,256                         ; 下一个U-SALT
        pop ecx
        loop .b4

        ; 在GDT中登记LDT描述符
        mov esi,[ebp+11*4]                  ; 从堆栈中取的TCB的基地址
        mov eax,[es:esi+0x0c]               ; LDT的起始线性地址
        movzx ebx,word [ed:esi+0x0a]        ; LDT段界限
        mov ecx,0x00408200                  ; LDT描述符
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [es:esi+0x10],cx                ; 登记LDT选择子到TCB中

        mov ebx,[es:esi+0x14]               ; 从TCB中获取TSS的线性地址
        mov [es:ebx+96],cx                  ; 填写TSS的LDT域
            
        mov word [es:ebx+0],0               ; 反向链=0
        
        mov dx,[es:esi+0x12]                ; 段长度（界限）
        mov [es:ebx+102],dx                 ; 填写TSS的I/O位图偏移域
        
        mov word [es:ebx+100],0             ; T=0

        mov eax,[es:0x04]                   ; 从任务的4GB地址空间获取入口点
        mov [es:ebx+32],eax                 ; 填写TSS的EIP域

        pushfd
        pop edx
        mov [es:ebx+36],edx                 ; 填写TSS的EFLAGS域
        
        ; 在GDT中登记TSS描述符
        mov eax,[es:esi+0x14]               ; 从TCB中获取TSS的起始线性地址
        movzx ebx,word [es:esi+0x12]        ; 段长度
        mov ecx,0x00408900                  ; TSS描述符，特权级0
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [es:esi+0x18],cx                ; 登记TSS选择子到TCB
        
        ; 创建用户的页目录
        ; 
        call sys_routine_seg_sel:create_copy_cur_pdir
        mov ebx,[es:esi+0x14]               ; 从TCB中获取TSS的线性地址
        mov dword [es:ebx+28],eax           ; 填写TSS的CR3（PDBP）域

        pop es
        pop ds
        
        popad

        ret 8
;---------------------------------------------------------------------
; 在TCB链上追加任务控制块
; @Param ECX=TCB线性基地址
;
append_to_tcb_link:

        push eax
        push edx
        push ds
        push es
            
        mov eax,core_data_seg_sel
        mov ds,eax
        mov eax,mem_0_4_gb_seg_sel
        mov es,eax

        mov dword [ed+ecx+0x00],0
        
        mov eax,[tcb_chain]
        or eax,eax
        jz .notcb

    .searc:
        mov edx,eax
        mov eax,[es:edx+0x00]
        or eax,eax
        jz .searc    

        mov [es:edx+0x00],ecx
        jmp .retpc

    .notcb:
        mov [tcb_chain],ecx

    .retpc:
        pop es
        pop ds
        pop edx
        pop eax

        ret
;---------------------------------------------------------------------
start:
        mov ecx,core_data_seg_sel
        mov ds,ecx

        mov ecx,mem_0_4_gb_seg_sel
        mov es,ecx
        
        mov ebx,message_0
        call sys_routine_seg_sel:put_string

        ; 显示处理器信息
                
        mov eax,0x80000002
        cpuid
        mov [cpu_brand + 0x00],eax
        mov [cpu_brand + 0x04],ebx
        mov [cpu_brand + 0x08],ecx
        mov [cpu_brand + 0x0c],edx
      
        mov eax,0x80000003
        cpuid
        mov [cpu_brand + 0x10],eax
        mov [cpu_brand + 0x14],ebx
        mov [cpu_brand + 0x18],ecx
        mov [cpu_brand + 0x1c],edx

        mov eax,0x80000004
        cpuid
        mov [cpu_brand + 0x20],eax
        mov [cpu_brand + 0x24],ebx
        mov [cpu_brand + 0x28],ecx
        mov [cpu_brand + 0x2c],edx

        mov ebx,cpu_brnd0                  ;显示处理器品牌信息 
        call sys_routine_seg_sel:put_string
        mov ebx,cpu_brand
        call sys_routine_seg_sel:put_string
        mov ebx,cpu_brnd1
        call sys_routine_seg_sel:put_string
 

        ; 准备打开分页机制

        ; 创建系统内核的页目录表PDT
        ; 页目录表清零
        mov ecx,1024                        ; 1024 个目录项
        mov ebx,0x00020000                  ; 页目录的物理地址
        xor esi,esi
    .b1:
        mov dword [es:ebx+esi],0x00000000   ; 页目录表项清零
        add esi,4
        loop  .b1

        ; 在页目录内创建指向页目录自己的目录项
        mov dword [es:ebx+4092],0x00020003

        ; 在页目录内创建与线性地址0x00000000对应的目录项
        mov dword [es:ebx+0],0x00021003     ; 写入目录项

        ; 创建与上面那个目录项相对应的页表，初始化页表项
        mov ebx,0x00021000
        xor eax,eax
        xor esi,esi
    .b2:
        mov edx,eax
        or edx,0x00000003
        mov [es:ebx+esi*4],edx              ; 登记页的物理地址
        add eax,0x1000                      ; 下一个相邻页的物理地址
        inc esi
        cmp esi,256                         ; 仅低端1MB内存对应的页才是有效的
        jl .b2

    .b3:                                    ; 其余的页表项置为无效
        mov dword [es:ebx+esi*4],0x00000000
        inc esi
        cmp esi,1024
        jl .b3
    
        ; 令CR3寄存器指向页目录，并正式开启页功能
        mov eax,0x00020000                  ; PCD=PWT=0
        mov cr3,eax

        mov eax,cr0
        or eax,0x80000000
        mov cr0,eax                         ; 开启分页机制
    
         ; 在页目录内创建与线性地址0x80000000对应的目录项
        mov ebx,0xfffff000                  ; 页目录自己的线性地址
        mov esi,0x80000000                  ; 映射的起始地址
        shr esi,22                          ; 线性地址的高10位是目录索引
        shl esi,2
        mov dword [es:ebx+esi],0x00021003   ; 写入目录项（页表的物理地址和属性）
                                            ; 目标单元的线性地址为0xFFFFF200

        ; 将GDT中的段描述符映射到线性地址0x80000000
        sgdt [pgdt]
    
        mov ebx,[pgdt+2]
    
        or dword [es:ebx+0x10+4],0x80000000
        or dword [es:ebx+0x18+4],0x80000000
        or dword [es:ebx+0x20+4],0x80000000
        or dword [es:ebx+0x28+4],0x80000000
        or dword [es:ebx+0x30+4],0x80000000
        or dword [es:ebx+0x38+4],0x80000000

        add dword [pgdt+2],0x80000000       ; GDTR也用的是线性地址

        lgdt [pgdt]
        
        jmp core_code_seg_sel:flush         ; 刷新段寄存器CS，启用高端线性地址

    flush:
        mov eax,core_stack_seg_sel
        mov es,eax
    
        mov eax,core_data_seg_sel
        mov ds,eax

        mov ebx,message_1
        call sys_routine_seg_sel:put_string

        ; 安装为整个系统服务的调用门。特权级之间的控制转移必须使用门
        mov edi,salt    
        mov ecx,salt_items
    .b4:
        push ecx
        mov eax,[edi+256]                   ; 32位偏移地址
        mov bx,[edi+260]                    ; 段选择子
        mov cx,1_11_0_1100_000_00000B       ; 特权级3的调用门（3以上的特权级才允许访问），0个参数（因为用寄存器传递参数，而没有用栈）
        call sys_routine_seg_sel:make_gate_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [edi+260],cx                    ; 回填门描述符选择子
        add edi,salt_item_len               ; 下一个条目
        pop ecx
        loop .b4

        ; 对门进行测试
        mov ebx,message_2
        call far [salt_1+256]               ; 通过门显示信息（偏移量将被忽略）
    
        ; 为程序管理程序的TSS分配内存空间
        mov ebx,[core_next_laddr]
        call sys_routine_seg_sel:alloc_inst_a_page
        add dword [core_next_laddr],4096

        ; 在程序管理器的TSS中设置必要的项目
        mov word [es:ebx+0],0               ; 反向链=0
        
        mov eax,cr3
        mov dword [es:ebx+28],eax           ; 登记CR3（PDBR）
        
        mov word [es:ebx+96],0              ; 没有LDT。处理器允许没有LDT的任务
        mov word [es:ebx+100],0             ; T=0
        mov word [es:ebx+102],103           ; 没有I/O位图。0特权级事实上不需要
        
        ; 创建程序管理器的TSS描述符， 并安装到GDT中
        mov eax,ebx                         ; TSS的起始线性地址
        mov ebx,103                         ; 段长度
        mov ecx,0x00408900                  ; TSS描述符，特权级0
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [program_man_tss+4],cx          ; 保存程序管理器的TSS描述符选择子
    
        ; 任务寄存器TR中的内容是任务存在的标志。该内容也决定了当前任务是谁
        ltr cx
        ; 现在可认为“任务管理器”任务正在执行中

        ; 创建用户任务的任务控制器
        mov ebx,[core_next_laddr]
        call sys_routine_seg_sel:alloc_inst_a_page
        add dword [core_next_laddr],4096

        mov dword [es:ebx+0x06],0           ; 用户任务局部空间分配从0开始
        mov word [es:ebx+0x0a],0xffff       ; 登记LDT初始的界限到TCB中
        mov ecx,ebx
        call append_to_tcb_link             ; 将TCB添加到TCB链中
    
        push dword 50                       ; 用户程序
        push ecx
    
        call load_relocate_program

        mov ebx,message_4
        call sys_routine_seg_sel:put_string

        call far [es:ecx+0x14]              ; 执行任务切换
    
        mov ebx,message_5
        call sys_routine_seg_sel:put_string

        hlt

core_code_end:

;=====================================================================
SECTION core_trail
core_end:
