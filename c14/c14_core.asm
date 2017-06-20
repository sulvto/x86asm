; x86汇编语言：从实模式到保护模式

core_code_seg_sel       equ     0x38
core_data_seg_sel       equ     0x30
sys_routine_seg_sel     equ     0x28
video_ram_seg_sel       equ     0x20
core_stack_seg_sel      equ     0x18
mem_0_4_gb_seg_sel      equ     0x08    

core_len        dd  core_endi                   ; #00
sys_routine_seg dd  section.sys_routine.start   ; #04
core_data_seg   dd  section.core_data.start     ; #08
core_code_seg   dd  section.core_code.start     ; #0c
core_entry      dd  start                       ; #10
                dw  core_code_seg_sel

;=====================================================================

        [bits 32]

;=====================================================================
SECTION sys_routine vstart=0
;---------------------------------------------------------------------
;
; 显示0终止的字符串并移动光标
; @Param DS:EBX=串地址
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
    .exit:
        pop ecx
        retf

;---------------------------------------------------------------------
;
; 在当前光标处显示一个字符，并推进光标 。仅用于段内调用
; @Param cl=字符 ascii 码
;
put_char:
        pushad
        
        ; 取光标位置
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
        inc al,dx
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
        pop  es

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
        mov word[es:dx],0x0720
        add bx,2
        loop .cls
        
        pop es
        pop ds

        mov bx,1920

    .set_cursor:
        mov dx,0x3d4
        mov al,0x0e
        out dx,al
        inc dx                                  ; 0x3d5
        mov al,bh
        out dx,al
        dec dx                                  ; 0x3d4
        mov al,0x0f
        out dx,al
        inc dx                                  ; 0x3d5
        mov al,bl
        out dx,al
    
        popad

        ret

;---------------------------------------------------------------------
;
; 从硬盘读取一个逻辑扇区
; @Param EAX 逻辑扇区号
; @Param DS:EBX 目标缓冲区
; @Retuen EBX=EBX+512
;
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
;
; @Param edx 要转换并显示的数字
;
put_hex_dword:
        pushad
        push ds

        mov ax,core_data_seg_sel                    ; 切换到核心数据段
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
;
; 分配内存
; @Param ecx 需要分配的字节数
; @Retuen ecx 起始线性地址
;
allocate_memory:
        push ds
        push eax
        push ebx
        
        mov eax,core_data_seg_sel
        mov ds,eax
        
        mov eax,[ram_alloc]
        add eax,ecx                             ; 下一次分配时的起始地址
        
        ; 这里应当有检测可用内存数量的指令

        mov ecx,[ram_alloc]                     ; 返回分配的起始地址
        
        mov ebx,eax
        and ebx,0xfffffffc
        add ebx,4
        test eax,0x00000003
        cmovnz eax,ebx
        mov [ram_alloc],eax                     ; 下一次从该地址分配内存
        
        pop ebx
        pop eax
        pop ds
        
        retf

;---------------------------------------------------------------------
;
; 在GDT内安装一个新的描述符
; @Param edx:eax 描述符
; @Retuen cx 描述符的选择子
;
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
        
        movzx ebx,word [pgdt]                   ; 界限值
        inc bx                                  ; 界限值加1，就是总字节数 也是下一个描述符偏移
        add ebx [pgdt+2]                        ; 下一个描述符的线性地址
        
        mov [es:ebx],eax
        mov [es:ebx+4],edx

        add word [pgdt],8                       ; 增加一个描述符的大小

        lgdt [pgdt]

        mov ax,[pgdt]                           ; 得到GDT界限值 16位
        xor dx,dx
        mov bx,8
        div bx                                  ; 除以8，去掉余数。得到索引号
        mov cx,ax   
        shl cx,3                                ; 索引号左移3位，留出TI位和RPL位
    
        pop es
        pop ds

        pop edx
        pop ebx
        pop eax

        retf

;---------------------------------------------------------------------
; 构造储存器和系统的段描述符
; @Param EAX 线性基地址
; @Param EBX 段界限
; @Param ECX 属性
; @Retuen EDX：EAX=描述符
;
make_seg_descriptor:
        mov edx,eax
        shl eax,16
        or ax,bx
        ; TODO
;---------------------------------------------------------------------
; 构造门的描述符（调用门等）
; @Param EAX 门代码在段内偏移地址
; @Param BX 门代码所在段的选择子
; @Param CX 段类型及属性
; @Retuen EDX:EAX 完整的描述符
;
make_gate_descriptor:
        push ebx
        push ecx
        mov edx,eax
        and edx,0xffff0000                      ; 得到偏移地址高16位
        or dx,cx                                ; 组装属性部分到EDX
        
        and eax,0x0000ffff                      ; 得到偏移地址低16位
        shl ebx,16
        or eax,ebx                              ; 组装段选择子部分
        
        pop ecx
        pop ebx
        
        retf

sys_routine_end:

;=====================================================================
SECTION core_data vstart=0
;---------------------------------------------------------------------
        pgdt        dw  0                       ; 用于设置和修改GDT
                    dd  0
        
        ram_alloc   dd 0x00100000               ; 下次分配内存时的起始地址
        ; 符号表
        salt:
        salt_1      dd  '@PrintString'
                times 256-($-salt_1) db 0
                    dd  put_string
                    dd sys_routine_seg_sel

        salt_2      dd  '@ReadDiskData'
                times 256-($-salt_2) db 0
                    dd  read_hard_disk_0
                    dd sys_routine_seg_sel

        salt_3      dd  '@PrintDwordAsHexString'
                times 256-($-salt_3) db 0
                    dd  put_hex_dword
                    dd sys_routine_seg_sel

        salt_4      dd  '@TerminateProgram'
                times 256-($-salt_4) db 0
                    dd  return_point
                    dd core_code_seg_sel

        salt_item_len   equ $-salt_4
        salt_items      equ ($-salt)/salt_item_len

        message_1        db  '  If you seen this message,that means we '
                         db  'are now in protect mode,and the system '
                         db  'core is loaded,and the video display '
                         db  'routine works perfectly.',0x0d,0x0a,0

        message_2        db  '  System wide CALL-GATE mounted.',0x0d,0x0a,0
        
        message_3        db  0x0d,0x0a,'  Loading user program...',0
        
        do_status        db  'Done.',0x0d,0x0a,0
        
        message_6        db  0x0d,0x0a,0x0d,0x0a,0x0d,0x0a
                         db  '  User program terminated,control returned.',0

        bin_hex          db '0123456789ABCDEF'
        
        core_buf        times 2048 db 0
        
        esp_pointer     dd  0
    
        cpu_brnd0       db  0x0d,0x0a,'  ',0
        cpu_brand       times 52 db 0
        cpu_brnd1       db 0x0d,0x0a,0x0d,0x0a,0
        
        tcb_chain       dd 0

core_data_end:

;=====================================================================
SECTION core_code vstart=0
;---------------------------------------------------------------------
fill_descriptor_in_ldt:
    ; TODO
;---------------------------------------------------------------------
;
; 加载并重定位用户程序
; @Params PUSH 逻辑扇区号
;         PUSH 任务控制块基地址
;
load_relocate_program:
        pushad
        
        push    ds
        push es
        
        mov ebp,esp
        mov ecx,mem_0_4_gb_seg_sel
        mov es,ecx
        
        ;   栈状态
        ;   
        ;   |-----------------------|
        ;   | 50                    |   <- SS: EBP + 12 * 4
        ;   |-----------------------|
        ;   |TCB线性地址            |   <- SS: EBP + 11 * 4
        ;   |-----------------------|
        ;   | EIP                   |
        ;   |-----------------------|
        ;   | 8个双字（通用寄存器） |   <- SS: EBP + 8
        ;   |-----------------------|
        ;   | 0        |  DS        |   <- SS: EBP + 4
        ;   |-----------------------|
        ;   | 0        |  ES        |   <- SS: EBP
        ;
        ;
        ;   SS：EBP+8 是pushad指令压入的8个双字
        mov esi,[ebp+11*4]                      ; 从堆栈中取得TCB的基地址 
                                                ; ebp 默认使用段寄存器SS
        ; 以下申请创建LDT所需要的内存
        mov ecx,160                             ; 允许安装20个LDT描述符
        call sys_routine_seg_sel:allocate_memory
        mov [es:esi+0x0c],ecx                   ; 登记LDT基地址到TCB中
        mov word [es:esi+0x0a],0xffff           ; 登记LDT初始的界限到TCB中
        ; 开始加载用户程序      
        mov eax,core_data_seg_sel
        mov ds,eax

        mov eax,[ebp+12*4]                      ; 从堆栈中取出用户程序起始扇区号
        mov ebx,core_buf                        ; 读取程序头部数据
        call sys_routine_seg_sel:read_hard_disk_0
        
        ; 以下判断整个程序有多大
        mov eax,[core_buf]                      ; 程序尺寸
        mov ebx,eax
        and ebx,0xfffffe00                      ; 使之512字节对齐（能被512整除的数低9位都为0）
        add ebx,512
        test eax,0x000001ff                     ; 
        cmovnz eax,ebx
                
        mov ecx,eax
        call sys_routine_seg_sel:allocate_memory
        mov [es:esi+0x06],ecx                   ; 登记程序加载基地址到TCB中
        
        mov ebx,ecx
        xor edx,edx
        mov ecx,512
        div ecx
        mov ecx,eax                             ; 总扇区数
        
        mov eax,mem_0_4_gb_seg_sel
        mov ds,eax
        
        mov eax,[ebp+12*4]                      ; 栈中获取起始扇区号
    
    .b1:
        call sys_routine_seg_sel:read_hard_disk_0
        inc eax
        loop .b1
        
        mov edi,[es:esi+0x06]                   ; 获得程序加载基地址i
        
        ; 建立程序头部段描述符
        mov eax,edi
        mov ebx,[edi+0x04]                      ; 段长度
        dec ebx                                 ; 段界限
        mov ecx,0x0040f200                      ; 字节粒度的数据段描述符，特级权3
        call sys_routine_seg_sel:make_seg_descriptor

        ; 安装头部段描述符到LDT中
        mov ebx,esi                             ; TCB的基地址
        call fill_descriptor_in_ldt

        or cx,0000_0000_0000_0011B              ; 设置选择子的特级权为3
        mov [es:esi+0x44],cx                    ; 登记程序头部段选择子到TCB
        mov [edi+0x04],cx                       ; 和头部内

        ; 建立程序代码段描述符
        mov eax,edi
        add eax,[edi+0x14]                      ; 代码起始线性地址
        mov ebx,[edi+0x18]                      ; 段长度
        dec ebx                                 ; 段界限
        mov ecx,0x0040f800                      ; 字节粒度的代码段描述符，特级权3
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                             ; TCB的基地址
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B              ; 设置选择子的特级权为3
        mov [edi+0x14],cx                       ; 登记代码段选择子到头部
        
        ; 建立程序数据段描述符
        mov eax,edi
        add eax,[edi+0x1c]                      ; 数据段起始线性地址
        mov ebx,[edi+0x20]                      ; 段长度
        dec ebx                                 ; 段界限
        mov ecx,0x0040f200                      ; 字节粒度的数据段描述符，特权级3
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                             ; TCB的基地址       
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B              ; 设置选择子的特级权为3
        mov [edi+0x1c],cx                       ; 登记数据段选择子到头部

        ; 建立程序堆栈段描述符
        mov ecx,[edi+0x0c]                      ; 4KB的倍率
        mov ebx,0x000fffff
        sub ebx,ecx                             ; 得到段界限
        mov eax,4096
        mul ecx
        mov ecx,eax
        call sys_routine_seg_sel:allocate_memory
        add eax,ecx                             ; 得到堆栈的高端物理地址
        mov ecx,0x00c0f600                      ; 字节粒度的堆栈段描述符，特权级3
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                             ; TCB的基地址       
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B              ; 设置选择子的特级权为3
        mov [edi+0x08],cx                       ; 登记堆栈段选择子到头部

        ; 重定位SALT
        mov eax,mem_0_4_gb_seg_sel              ; 通过4GB段访问用户程序头部
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

        mov ecx,64                                  ; 检索表中。每条目的比较次数
        repe cmpsd                                  ; 每次比较4字节x64次=256（全部）。 ESI,EDI会递减
        jnz .b4 
        mov eax,[esi]                               ; 若匹配，则esi恰好指向其后的地址
        mov [es:edi-256],eax                        ; 将字符串改写成偏移地址
        mov ax,[esi+4]
        or ax,0000000000000011B                     ; 以用户程序自己的特权级使用调用门，故RPL=3
        mov [es:edi-252],ax                         ; 回填调用门选择子
        
    .b4:
        pop ecx
        pop esi
        add esi,salt_item_len
        pop edi                                     ; 从头比较
        loop .b3

        pop edi
        add edi,256
        pop ecx
        loop .b2

        mov esi.[ebp+11*4]                          ; 从堆栈中取得TCB的地址
        
        ; 创建0特级权堆栈
        mov ecx,4096
        mov eax,ecx
        mov [es:esi+0x1a],ecx
        shr dword [es:esi+0x1a],12                  ; 登记0特级权堆栈尺寸到TCB
        call sys_routine_seg_sel:allocate_memory
        add eax,ecx                                 ; 堆栈必须使用高端地址为基地址
        mov [es:esi+0x1e],eax                       ; 登记0特级权堆栈基地址到TCB
        mov ebx,0xffffe                             ; 段长度（界限）
        mov ecx,0x00c09600                          ; 4KB粒度，读写，特级权0
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                                 ; TCB的基地址
        call fill_descriptor_in_ldt
        ; or cx,0000_0000_0000_0000
        mov [es:esi+0x22],cx                        ; 登记0特权级堆栈选择子到TCB
        mov dword [es:esi+0x24],0                   ; 登记0特权级堆栈初始ESP到TCB
        
        ; 创建1特级权堆栈
        mov ecx,4096
        mov eax,ecx
        mov [es:esi+0x28],ecx
        shr dword [es:esi+0x28],12                  ; 登记1特级权堆栈尺寸到TCB
        call sys_routine_seg_sel:allocate_memory
        add eax,ecx                                 ; 堆栈必须使用高端地址为基地址
        mov [es:esi+0x2c],eax                       ; 登记1特级权堆栈基地址到TCB
        mov ebx,0xffffe                             ; 段长度（界限）
        mov ecx,0x00c0b600                          ; 4KB粒度，读写，特级权1
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                                 ; TCB的基地址
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0001
        mov [es:esi+0x30],cx                        ; 登记1特权级堆栈选择子到TCB
        mov dword [es:esi+0x32],0                   ; 登记1特权级堆栈初始ESP到TCB

        ; 创建2特级权堆栈
        mov ecx,4096
        mov eax,ecx
        mov [es:esi+0x36],ecx
        shr dword [es:esi+0x36],12                  ; 登记2特级权堆栈尺寸到TCB
        call sys_routine_seg_sel:allocate_memory
        add eax,ecx                                 ; 堆栈必须使用高端地址为基地址
        mov [es:esi+0x3a],eax                       ; 登记2特级权堆栈基地址到TCB
        mov ebx,0xffffe                             ; 段长度（界限）
        mov ecx,0x00c0d600                          ; 4KB粒度，读写，特级权2
        call sys_routine_seg_sel:make_seg_descriptor
        mov ebx,esi                                 ; TCB的基地址
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0010
        mov [es:esi+0x3e],cx                        ; 登记2特权级堆栈选择子到TCB
        mov dword [es:esi+0x40],0                   ; 登记2特权级堆栈初始ESP到TCB

        ; 在GDT中登记LDT描述符
        mov eax,[es:esi+0x0c]                       ;  LDT的起始线性地址    
        movzx ebx,word [es:esi+0x0a]                ; LDT段界限
        mov ecx,0x00408200                          ; LDT描述符，特权级0
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [es:esi+0x10],cx                        ; 登记LDT选择子到TCB中
    
        ; 创建用户程序的TSS
        mov ecx,104                                 ; tss的基本尺寸
        mov [es:esi+0x12],cx                        ; 登记TSS界限值到TCB
        dec word [es:esi+0x12]                      ; TSS界限值为103
        call sys_routine_seg_sel:allocate_memory
        mov [es:esi+0x14],ecx                       ; 登记TSS基地址到TCB
        
        ; 登记基本的TSS表格内容
        mov word [es:ecx+0],0                       ; 反向链=0
        
        mov edx,[es:esi+0x24]                       ; 0特权级堆栈初始ESP
        mov [es:ecx+4],edx                          ; 登记到TSS （ESP0）

        mov ex,[es:esi+0x22]                        ; 0特权级堆栈段选择子
        mov [es:ecx+8],edx                          ; 登记到TSS （SS0）

        mov edx,[es:esi+0x32]                       ; 1特权级堆栈初始ESP
        mov [es:ecx+12],edx                         ; 登记到TSS （ESP1）

        mov dx,[es:esi+0x30]                        ; 0特权级堆栈段选择子
        mov [es:ecx+16],edx                         ; 登记到TSS （SS1）

        mov edx,[es:esi+0x40]                       ; 2特权级堆栈初始ESP
        mov [es:ecx+20],edx                         ; 登记到TSS （ESP2）
                                                            
        mov dx,[es:esi+0x3e]                        ; 2特权级堆栈段选择子
        mov [es:ecx+24],edx                         ; 登记到TSS （SS2）
 
        mov dx,[es:esi+0x10]                        ; 任务的LDT选择子    
        mov [es:ecx+96],dx                          ; 登记到TSS

        mov word [es:ecx+100],0                     ; T=0

        ; 在GDT中登记TSS描述符
        mov eax,[es:esi+0x14]                       ; TSS的起始线性地址
        movzx ebx,word [es:esi+0x12]                ; 段长度
        mov ecx,0x00408900                          ; TSS描述符，特权级0
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [es:esi+0x18],cx                        ; 登记TSS选择子到TCB
        
        pop es
        pop ds
        
        popad
        
        ret 8                                       ; 丢弃调用本过程前压入的参数

;---------------------------------------------------------------------

;
;在TCB链上追加任务控制块
; @Param ECX=TCB线性基地址
;
append_to_tcb_link:
        push eax
        push edx
        push ds
        push es
        
        mov eax,core_data_seg_sel               ; ds指向内核数据段
        mov ds,eax
        mov eax,mem_0_4_gb_seg_sel              ; es指向0～4GB段
        mov es,eax

        mov dword   [es:ecx+0x00],0             ; 当前TCB指针域清零，以指示这是最后一个TCB
        
        mov eax,[tcb_chain]                     ; 链表头
        or eax,eax                              ; 链表为空？
        jz .notcb

    .searc:                                     ; 找到最后一个TCB
        mov edx,eax
        mov eax,[es:edx+0x00]
        or eax,eax
        jnz .searc

        mov [es:edx+0x00],ecx
        jmp .retpc

    .notcb:
        mov [tcb_chain],ecx                     ; 若为空表，直接令表头指针指向TCB

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
        
        mov ebx,message_1
        call sys_routine_seg_sel:put_string

        ; 显示处理器品牌信息
        mov eax,0x80000002
        cpuid
        mov [cpu_brand+0x00],eax
        mov [cpu_brand+0x04],ebx
        mov [cpu_brand+0x08],ecx
        mov [cpu_brand+0x0c],edx

        mov eax,0x80000003
        cpuid
        mov [cpu_brand+0x10],eax
        mov [cpu_brand+0x14],ebx
        mov [cpu_brand+0x18],ecx
        mov [cpu_brand+0x1c],edx

        mov eax,0x80000004
        cpuid
        mov [cpu_brand+0x20],eax
        mov [cpu_brand+0x24],ebx
        mov [cpu_brand+0x28],ecx
        mov [cpu_brand+0x2c],edx

        mov ebx,cpu_brnd0
        call sys_routine_seg_sel:put_string
        mov ebx,cpu_brand
        call sys_routine_seg_sel:put_string
        mob ebx,cpu_brnd1
        call sys_routine_seg_sel:put_string

        ; 安装为整个系统服务的调用门。特级权之间的控制转移必须使用门
        mov edi,salt
        mov ecx,salt_items

    .b3:
        push ecx
        mov eax,[edi+256]                       ; 该条目入口点的32位偏移地址
        mov bx,[edi+260]                        ; 该条目入口点的段选择子
        mov cx,1_11_0_1100_000_00000B           ; 特级权3的调用门，0个参数
        call sys_routine_seg_sel:make_gate_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [edi+260],cx
        add edi,salt_item_len                   ; 指向下一个C-SALT条目
        pop ecx
        loop .b3
   
        ; 进行门测试
        mov ebx,message_2
        call far [salt_1+256]                   ; 通过门显示信息（偏移量将被忽略）
        
        mov ebx,message_3
        call sys_routine_seg_sel:put_string     ; 内核中调用例程不需要通过门
        
        ; 创建任务控制块，为了方便而设立
        mov ecx,0x46
        call sys_routine_seg_sel:allocate_memory
        call append_to_tcb_link                 ; 将任务控制块追加到TCB链表
        push dword 50                           ; 用户程序位于逻辑50扇区
        push ecx                                ; 压如任务控制块起始线性地址
        
        call load_relocate_program

        mov bx,do_status
        call sys_routine_seg_sel:put_string
        
        mov eax,mem_0_4_gb_seg_sel
        mov ds,eax                              
        
        ltr [ecx+0x18]                          ; 加载任务状态段
        lldt [ecx+0x10]                         ; 加载LDT

        mov eax,[ecx+0x44]
        mov ds,eax

        push dword [0x08]                       ; 调用前的堆栈段选择子
        push dword 0                            ; 调用前的esp
        push dword [0x14]                       ; 调用前的代码段选择子
        push dword [0x10]                       ; 调用前的eip
        
        retf

return_point:                                   ; 用户程序返回点    
        mov eax,core_code_seg_sel           
        mov ds,eax
        
        mov ebx,message_6
        call sys_routine_seg_sel:put_string

        hlt

core_code_end:

;---------------------------------------------------------------------
SECTION core_trail
;---------------------------------------------------------------------
core_end:
