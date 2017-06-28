; x86汇编语言：从实模式到保护模式

        ; 常量
        core_code_seg_sel   equ 0x38
        core_data_seg_sel   equ 0x30
        sys_routine_seg_sel equ 0x28
        video_ram_seg_sel   equ 0x20
        core_stack_seg_sel  equ 0x18
        mem_0_4_gb_seg_sel  equ 0x08

        ; 系统核心的头部
        core_len        dd core_end                     ; #00
        sys_routine_seg dd section.sys_routine.start    ; #04
        core_data_seg   dd section.core_data.start      ; #08
        core_code_seg   dd section.core_code.start      ; #0c
        core_entry      dd start                        ; #10
                        dw core_code_seg_sel

;=====================================================================
        [bits 32]
SECTION sys_routine vstart=0
;---------------------------------------------------------------------
; 字符串显示
put_string:
        push ecx
    .getc:
        mov cl,[ebx]
        or cl,cl
        jz .exit
        call put_char
        inc ebx
        jmp .getc

    .exit:
        pop ecx
        retf

;---------------------------------------------------------------------
put_char:
        pushad
        
        mov dx,0x3d4
        mov al,0x0e
        out dx,al
        inc dx
        in al,dx
        mov ah,al
        
        dec dx
        mov al,0x0f
        out dx,al
        inc dx
        in al,ax
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
        shl bc,1
        mov [es:bx],cl
        pop es

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
; @Param EAX=逻辑扇区号
; @Param DS:EBX=目标缓冲区地址
; @Return EBX=EBX+512
read_hard_disk_0:
        push eax
        push ecx
        push edx
        
        push eax
        
        mov dx,0x1f2
        mov al,1
        out dx,al
        
        inc dx
        pop eax
        out dx,al

        inc dx
        mov cl,8
        shr eax,cl
        out dx,al

        inc dx
        shr eax,cl
        out dx,al

        inc dx
        shr eax,cl  
        or al,0xe0
        out dx,al
    
        inc dx
        mov al,0x20
        out dx,al

    .waits:
        in al,dx
        and al,0x88
        cmp al,0x08
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

        retf

;---------------------------------------------------------------------

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
        retf

;---------------------------------------------------------------------
; 分配内存
; @Param ECX= 分配字节数
; @Return ECX= 起始线性地址 
allocate_memory:
        push ds
        push eax
        push ebx

        mov eax,core_data_seg_sel
        mov dx,eax
        
        mov eax,[ram_alloc]
        add eax,ecx
    
        mov ecx,[ram_alloc]

        mov ebx,eax
        and ebx,0xfffffffc
        add ebx,4
        test eax,0x00000003
        cmovnz eax,ebx
        mov [ram_alloc],eax

        pop edx
        pop eax
        pop ds
        
        retf

;---------------------------------------------------------------------

set_up_gdt_descriptor:
        push eax
        push ebx
        push edx

        push ds
        push es

        mov edx,core_data_seg_sel
        mov ds,ebx

        sgdt [pgdt]
    
        mov ebx,mem_0_4_gb_seg_sel
        mov es,ebx

        movzx ebx,word [pgdt]
        inc bx
        add ebx,[pgdt+2]

        mov [es:ebx],eax
        mov [es:ebx+4],edx

        add word [pgdt],8

        lgdt [pgdt]

        mov ax,[pgdt]
        xor dx,dx
        mov bx,8
        div bx  
        mov cx,ax
        shl cx,3

        pop es
        pop ds

        pop edx
        pop ebx
        pop eax

        retf

;---------------------------------------------------------------------

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
terminate_current_task:
    ; TODO

sys_routine_end:

;=====================================================================
SECTION core_data vstart=0
        pgdt        dw  0
                    dd  0

        ram_alloc   dd  0x00100000

        salt:
        salt_1      db  '@PrintString'
                times 256-($-salt_1) db 0
                    dd put_string
                    dw  sys_routine_seg_sel

        salt_2      db  '@ReadDiskData'
                times 256-($-salt_2) db 0
                    dd read_hard_disk_0
                    dw  sys_routine_seg_sel

        salt_3      db  '@PrintDWordAsHexString'
                times 256-($-salt_3) db 0
                    dd put_hex_dword
                    dw  sys_routine_seg_sel
                                                   
        salt_4      db  '@TerminateProgram'
                times 256-($-salt_4) db 0
                    dd terminate_current_task
                    dw  sys_routine_seg_sel

        salt_item_len   equ $-salt_4
        salt_items      equ ($-salt)/salt_item_len

        message_1;;TODO








start:
        mov ecx,core_data_seg_sel
        mov ds,ecx
        mov ecx,mem_0_4_gb_seg_sel
        mov es,ecx

        mov ebx,message_1
        call sys_routine_seg_sel:put_string

        ; 显示处理器品牌信息
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

        mov ebx,cpu_brnd0
        call sys_routine_seg_sel:put_string
        mov ebx,cpu_brand
        call sys_routine_seg_sel:put_string
        mov ebx,cpu_brnd1
        call sys_routine_seg_sel:put_string

        ; 安装为整个系统服务的调用门。特权级之间的控制转移必须使用门
        mov edi,salt                        ; C-SALT表的起始位置
        mov ecx,salt_items                  ; C-SALT表的条目数量

    .b3:
        push ecx
        mov eax,[edi+256]                   ; 该条目入口点的32位偏移地址
        mov bx,[edi+260]                    ; 该条目入口点的段选择子
        mov cx,1_11_0_1100_000_00000B       ; 
        call sys_routine_seg_sel:make_gate_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [edi+260],cx                    ; 将返回的门描述符选择子回填
        add edi,salt_item_len               ; 下一个C-SALT
        pop ecx
        loop .b3

        ; 对门进行测试
        mov ebx,message_2
        call far [salt_1+256]               ; 通过门显示信息

        ; 为程序管理器的TSS分配空间
        mov ecx,104                         ; 为该任务的TSS分配内存
        call sys_routine_seg_sel:allocate_memory
        mov [prgman_tss+0x00],ecx           ; 保存程序管理器的TSS地址

        ; 在程序管理器的TSS中设置必要的项目
        mov word [es:ecx+96],0              ; 没有LDT。处理器允许没有LDT的任务
        mov word [es:ecx+102],103           ; 没有I/O位图。0特权级事实上不需要
        mov word [es:ecx+0],0               ; 反向链=0
        mov dword [es:ecx+28],0             ; 登记CR3（PDBP）
        mov word [es:ecx+100],0             ; T=0
                                            
        ;  创建TSS描述符，并安装到GDT中
        mov eax,ecx                         ; TSS的起始线性地址 
        mov ebx,103                         ; 段长度
        mov ecx,0x00408900                  ; TSS描述符，特权级0
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [prgman_tss+0x04],cx            ; 保存程序管理器的TSS描述符选择子
        
        ; 任务寄存器TR中的内容存在的标志，该内容也决定了当前任务是谁
        ; 下面的指令为当前正在执行的0特权级任务“程序管理器”后补手续（TSS）
        ltr cx

        ; 现在可以认为“程序管理器”任务正在执行中
        mov ebx,prgman_msg1
        call sys_routine_seg_sel:put_string

        mov ecx,0x46
        call sys_routine_seg_sel:allocate_memory
        call append_to_tcb_link             ; 将此TCB添加到TCB链中

        push dword 50                       ; 用户程序位于逻辑50扇区
        push ecx                            ; 压入任务控制块起始线性地址
    
        call load_relocate_program
    
        call far [es:ecx+0x14]              ; 执行任务切换。

        ; 重新加载并切换任务
        mov ebx,prgman_msg2
        call sys_routine_seg_sel:put_string

        mov ecx,0x46
        call sys_routine_seg_sel:allocate_memory
        call append_to_tcb_link
        
        push dword 50
        push ecx

        call load_relocate_program

        jmp far [es:ecx+0x14]
    
        mov ebx,prgman_msg3
        call sys_routine_seg_sel:put_string

        hlt

core_code_end:

;---------------------------------------------------------------------
SECTION core_trail
;---------------------------------------------------------------------

core_end:
        
