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
        mov ds,eax
        
        mov eax,[ram_alloc]
        add eax,ecx
    
        mov ecx,[ram_alloc]

        mov ebx,eax
        and ebx,0xfffffffc
        add ebx,4
        test eax,0x00000003
        cmovnz eax,ebx
        mov [ram_alloc],eax

        pop ebx
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
        
        mov ebx,core_data_seg_sel
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
; 终止当前任务
;
;
terminate_current_task:
        pushfd
        mov edx,[esp]
        add esp,4
        
        mov eax,core_data_seg_sel
        mov ds,eax
        
        test dx,0100_0000_0000_0000B        ; test NT 位
        jnz .b1
        mov ebx,core_msg1
        call sys_routine_seg_sel:put_string
        jmp far [prgman_tss]

    .b1:
        mov ebx,core_msg0
        call sys_routine_seg_sel:put_string
        iretd
        

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

        message_1   db  '  If you seen this message,that means we '
                    db  'are now in protect mode,and the system '
                    db  'core is loaded,and the video display '
                    db  'routine works perfectly.',0x0d,0x0a,0

        message_2   db  '  System wide CALL-GATE mounted.',0x0d,0x0a,0

        bin_hex     db  '0123456789ABCDEF'
    
        core_buf    times 2048 db 0

        cpu_brnd0   db  0x0d,0x0a,'  ',0
        cpu_brand   times 52 db 0
        cpu_brnd1   db  0x0d,0x0a,0x0d,0x0a,0

        ; 任务控制链
        tcb_chain   dd  0

        ; 任务管理器的任务信息
        prgman_tss  dd  0               ; 任务管理器的TSS基地址
                    dw  0               ; 任务管理器的TSS描述表



        prgman_msg1      db  0x0d,0x0a
                         db  '[PROGRAM MANAGER]: Hello! I am Program Manager,'
                         db  'run at CPL=0.Now,create user task and switch '
                         db  'to it by the CALL instruction...',0x0d,0x0a,0
                
        prgman_msg2      db  0x0d,0x0a
                         db  '[PROGRAM MANAGER]: I am glad to regain control.'
                         db  'Now,create another user task and switch to '
                         db  'it by the JMP instruction...',0x0d,0x0a,0
                
        prgman_msg3      db  0x0d,0x0a
                         db  '[PROGRAM MANAGER]: I am gain control again,'
                         db  'HALT...',0

        core_msg0        db  0x0d,0x0a
                         db  '[SYSTEM CORE]: Uh...This task initiated with '
                         db  'CALL instruction or an exeception/ interrupt,'
                         db  'should use IRETD instruction to switch back...'
                         db  0x0d,0x0a,0

        core_msg1        db  0x0d,0x0a
                         db  '[SYSTEM CORE]: Uh...This task initiated with '
                         db  'JMP instruction,  should switch to Program '
                         db  'Manager directly by the JMP instruction...'
                         db  0x0d,0x0a,0


core_data_end:

;=====================================================================

SECTION core_code vstart=0
;---------------------------------------------------------------------
; 在LDT内安装一个新的描述符
; @Param EDX：EAX 描述符
; @Param      EBX=TCB基地址
; @Return CX=描述符的选择子
fill_descriptor_in_ldt:
        push eax
        push edx
        push edi
        push ds

        mov ecx,mem_0_4_gb_seg_sel
        mov ds,ecx
        
        mov edi,[ebx+0x0c]
        
        xor ecx,ecx
        mov cx,[ebx+0x0a]
        inc cx

        mov [edi+ecx+0x00],eax
        mov [edi+ecx+0x04],edx
        
        add cx,8
        dec cx
    
        mov [ebx+0x0a],cx

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
; @Param PUSH 任务控制块基地址
; 
load_relocate_program:
        pushad

        push ds
        push es
    
        mov ebp,esp
        
        mov ecx,mem_0_4_gb_seg_sel
        mov es,ecx
    
        mov esi,[ebp+11*4]

        mov ecx,160
        call sys_routine_seg_sel:allocate_memory
        mov [es:esi+0x0c],ecx
        mov word [es:esi+0x0a],0xffff

        mov eax,core_data_seg_sel
        mov ds,eax
    
        mov eax,[ebp+12*4]
        mov ebx,core_buf
        call sys_routine_seg_sel:read_hard_disk_0

        mov eax,[core_buf]
        mov ebx,eax
        and ebx,0xfffffe00
        add ebx,512
        test eax,0x000001ff
        cmovnz  eax,ebx
        
        mov ecx,eax
        call sys_routine_seg_sel:allocate_memory
        mov [es:esi+0x06],ecx
    
        mov ebx,ecx
        xor edx,edx
        mov ecx,512
        div ecx
        mov ecx,eax

        mov eax,mem_0_4_gb_seg_sel
        mov ds,eax

        mov eax,[ebp+12*4]
    .b1:
        call sys_routine_seg_sel:read_hard_disk_0
        inc eax
        loop .b1

        mov edi,[es:esi+0x06]

        mov eax,edi
        mov ebx,[edi+0x04]
        dec ebx
        mov ecx,0x0040f200
        call sys_routine_seg_sel:make_seg_descriptor
 
        mov ebx,esi
        call fill_descriptor_in_ldt

        or cx,0000_0000_0000_0011B
        mov [es:esi+0x44],cx
        mov [edi+0x04],cx

        mov eax,edi
        add eax,[edi+0x14]
        mov ebx,[edi+0x18]
        dec ebx
        mov ecx,0x0040f800
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B
        mov [edi+0x14],cx

        mov eax,edi
        add eax,[edi+0x1c]
        mov ebx,[edi+0x20]
        dec ebx
        mov ecx,0x0040f200
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B
        mov [edi+0x1c],cx
        
        mov ecx,[edi+0x0c]
        mov ebx,0x000fffff
        sub ebx,ecx
        mov eax,4096
        mul ecx
        mov ecx,eax
        call sys_routine_seg_sel:allocate_memory
        add eax,ecx
        mov ecx,0x00c0f600
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B
        mov [edi+0x08],cx
    
        mov eax,mem_0_4_gb_seg_sel
        mov es,eax
        
        mov eax,core_data_seg_sel
        mov ds,eax

        cld

        mov ecx,[es:edi+0x24]
        add edi,0x28
    .b2:
        push ecx
        push edi

        mov ecx,salt_items
        mov esi,salt
    .b3:
        push edi
        push esi
        push ecx

        mov ecx,64
        repe cmpsd
        jnz .b4
        mov eax,[esi]
        mov [es:edi-256],eax
        mov ax,[esi+4]
        or ax,0000000000000011B

        mov [es:edi-252],ax

    .b4:
        
        pop ecx
        pop esi
        add esi,salt_item_len
        pop edi
        loop .b3

        pop edi
        add edi,256
        pop ecx
        loop .b2 

        mov esi,[ebp+11*4]

        
         ;创建0特权级堆栈
         mov ecx,4096
         mov eax,ecx                        ;为生成堆栈高端地址做准备 
         mov [es:esi+0x1a],ecx
         shr dword [es:esi+0x1a],12         ;登记0特权级堆栈尺寸到TCB 
         call sys_routine_seg_sel:allocate_memory
         add eax,ecx                        ;堆栈必须使用高端地址为基地址
         mov [es:esi+0x1e],eax              ;登记0特权级堆栈基地址到TCB 
         mov ebx,0xffffe                    ;段长度（界限）
         mov ecx,0x00c09600                 ;4KB粒度，读写，特权级0
         call sys_routine_seg_sel:make_seg_descriptor
         mov ebx,esi                        ;TCB的基地址
         call fill_descriptor_in_ldt
         ;or cx,0000_0000_0000_0000          ;设置选择子的特权级为0
         mov [es:esi+0x22],cx               ;登记0特权级堆栈选择子到TCB
         mov dword [es:esi+0x24],0          ;登记0特权级堆栈初始ESP到TCB
      
         ;创建1特权级堆栈
         mov ecx,4096
         mov eax,ecx                        ;为生成堆栈高端地址做准备
         mov [es:esi+0x28],ecx
         shr dword [es:esi+0x28],12               ;登记1特权级堆栈尺寸到TCB
         call sys_routine_seg_sel:allocate_memory
         add eax,ecx                        ;堆栈必须使用高端地址为基地址
         mov [es:esi+0x2c],eax              ;登记1特权级堆栈基地址到TCB
         mov ebx,0xffffe                    ;段长度（界限）
         mov ecx,0x00c0b600                 ;4KB粒度，读写，特权级1
         call sys_routine_seg_sel:make_seg_descriptor
         mov ebx,esi                        ;TCB的基地址
         call fill_descriptor_in_ldt
         or cx,0000_0000_0000_0001          ;设置选择子的特权级为1
         mov [es:esi+0x30],cx               ;登记1特权级堆栈选择子到TCB
         mov dword [es:esi+0x32],0          ;登记1特权级堆栈初始ESP到TCB

         ;创建2特权级堆栈
         mov ecx,4096
         mov eax,ecx                        ;为生成堆栈高端地址做准备
         mov [es:esi+0x36],ecx
         shr dword [es:esi+0x36],12               ;登记2特权级堆栈尺寸到TCB
         call sys_routine_seg_sel:allocate_memory
         add eax,ecx                        ;堆栈必须使用高端地址为基地址
         mov [es:esi+0x3a],ecx              ;登记2特权级堆栈基地址到TCB
         mov ebx,0xffffe                    ;段长度（界限）
         mov ecx,0x00c0d600                 ;4KB粒度，读写，特权级2
         call sys_routine_seg_sel:make_seg_descriptor
         mov ebx,esi                        ;TCB的基地址
         call fill_descriptor_in_ldt
         or cx,0000_0000_0000_0010          ;设置选择子的特权级为2
         mov [es:esi+0x3e],cx               ;登记2特权级堆栈选择子到TCB
         mov dword [es:esi+0x40],0          ;登记2特权级堆栈初始ESP到TCB        
        
         ;在GDT中登记LDT描述符
         mov eax,[es:esi+0x0c]              ;LDT的起始线性地址
         movzx ebx,word [es:esi+0x0a]       ;LDT段界限
         mov ecx,0x00408200                 ;LDT描述符，特权级0
         call sys_routine_seg_sel:make_seg_descriptor
         call sys_routine_seg_sel:set_up_gdt_descriptor
         mov [es:esi+0x10],cx               ;登记LDT选择子到TCB中
       
         ;创建用户程序的TSS
         mov ecx,104                        ;tss的基本尺寸
         mov [es:esi+0x12],cx              
         dec word [es:esi+0x12]             ;登记TSS界限值到TCB 
         call sys_routine_seg_sel:allocate_memory
         mov [es:esi+0x14],ecx              ;登记TSS基地址到TCB
      
         ;登记基本的TSS表格内容
         mov word [es:ecx+0],0              ;反向链=0
      
         mov edx,[es:esi+0x24]              ;登记0特权级堆栈初始ESP
         mov [es:ecx+4],edx                 ;到TSS中
      
         mov dx,[es:esi+0x22]               ;登记0特权级堆栈段选择子
         mov [es:ecx+8],dx                  ;到TSS中
      
         mov edx,[es:esi+0x32]              ;登记1特权级堆栈初始ESP
         mov [es:ecx+12],edx                ;到TSS中

         mov dx,[es:esi+0x30]               ;登记1特权级堆栈段选择子
         mov [es:ecx+16],dx                 ;到TSS中

         mov edx,[es:esi+0x40]              ;登记2特权级堆栈初始ESP
         mov [es:ecx+20],edx                ;到TSS中

         mov dx,[es:esi+0x3e]               ;登记2特权级堆栈段选择子
         mov [es:ecx+24],dx                 ;到TSS中

         mov dx,[es:esi+0x10]               ;登记任务的LDT选择子
         mov [es:ecx+96],dx                 ;到TSS中
      
         mov dx,[es:esi+0x12]               ;登记任务的I/O位图偏移
         mov [es:ecx+102],dx                ;到TSS中 
      
         mov word [es:ecx+100],0            ;T=0
      
         mov dword [es:ecx+28],0            ;登记CR3(PDBR)
      
         ;访问用户程序头部，获取数据填充TSS 
         mov ebx,[ebp+11*4]                 ;从堆栈中取得TCB的基地址
         mov edi,[es:ebx+0x06]              ;用户程序加载的基地址 

         mov edx,[es:edi+0x10]              ;登记程序入口点（EIP） 
         mov [es:ecx+32],edx                ;到TSS

         mov dx,[es:edi+0x14]               ;登记程序代码段（CS）选择子
         mov [es:ecx+76],dx                 ;到TSS中

         mov dx,[es:edi+0x08]               ;登记程序堆栈段（SS）选择子
         mov [es:ecx+80],dx                 ;到TSS中

         mov dx,[es:edi+0x04]               ;登记程序数据段（DS）选择子
         mov word [es:ecx+84],dx            ;到TSS中。注意，它指向程序头部段
      
         mov word [es:ecx+72],0             ;TSS中的ES=0

         mov word [es:ecx+88],0             ;TSS中的FS=0

         mov word [es:ecx+92],0             ;TSS中的GS=0

         pushfd
         pop edx
         
         mov dword [es:ecx+36],edx          ;EFLAGS

         ;在GDT中登记TSS描述符
         mov eax,[es:esi+0x14]              ;TSS的起始线性地址
         movzx ebx,word [es:esi+0x12]       ;段长度（界限）
         mov ecx,0x00408900                 ;TSS描述符，特权级0
         call sys_routine_seg_sel:make_seg_descriptor
         call sys_routine_seg_sel:set_up_gdt_descriptor
         mov [es:esi+0x18],cx               ;登记TSS选择子到TCB

         pop es                             ;恢复到调用此过程前的es段 
         pop ds                             ;恢复到调用此过程前的ds段
      
         popad
      
         ret 8                              ;丢弃调用本过程前压入的参数 

;---------------------------------------------------------------------
; 追加任务控制块到TCB链
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

        mov dword [es:ecx+0x00],0

        mov eax,[tcb_chain]
        or eax,eax
        jz .notcb

    .searc:
        mov edx,eax
        mov eax,[es:edx+0x00]
        or eax,eax
        jnz .searc

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
        
