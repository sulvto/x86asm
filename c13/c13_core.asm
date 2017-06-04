; x86汇编语言：从实模式到保护模式

; 常量
core_code_seg_sel   equ 0x38    ; 内核代码段选择子
core_data_seg_sel   equ 0x30    ; 内核数据段选择子
sys_routine_seg_sel equ 0x28    ; 系统公共例程代码段选择子
video_ram_seg_sel   equ 0x20    
core_stack_seg_sel  equ 0x18    ; 内核堆栈段选择子
mem_0_4_gb_seg_sel equ 0x08    ; 整个0-4G内存的段的选择子

;---------------------------------------------------------------------

; 系统核心的头部，用于加载核心程序
core_len        dd  core_end                    ; 核心程序总长度     #00
sys_routine_seg dd  section.sys_routine.start   ; 系统公用例程段位置 #04
core_data_seg   dd  section.core_data.start     ; 核心数据段位置     #08
core_code_seg   dd  section.core_code.start     ; 核心代码段位置    #0c
core_entry      dd  start                       ; 核心代码段入口    #10
                dw  core_code_seg_sel           



;=====================================================================
    [bits 32]
;=====================================================================
SECTION sys_routine vstart=0                       ; 系统公共例程代码段
; ----------------------------------------------------------------

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
    .exit:
        pop ecx
        retf

; ----------------------------------------------------------------
put_char:
        pushad
        
        ; 以下取当前光标位置
        mov dx,0x3d4
        mov al,0x0e
        out dx,al
        inc dx                  ; 0x3d5
        in al,dx                
        mov ah,al
        
        dec dx
        mov al,0x0f
        out dx,al
        inc dx                  ; 0x3d5
        in al,dx                ; 低字
        mov bx,ax               

        cmp cl,0x0d             ; 回车符？
        jnz  .put_0a
        mov ax,bx
        mov bl,80
        div bl
        mul bl  
        mov bx,ax
        jmp .set_cursor

    .put_0a:
        cmp cl,0x0a             ; 换行符？
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

        ; 
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
        inc dx                  ; 0x3d5
        mov al,bh
        out dx,al
        dec dx                  ; 0x3d4
        mov al,0x0f
        out dx,al
        inc dx                  ; 0x3d5
        mov al,bl
        out dx,al
    
        popad
        ret

;---------------------------------------------------------------------------

;
; @Param EAX 逻辑扇区号
; @Param DS:EBX 目标缓冲区地址
; @Return EBX=EBX+512
;
read_hard_disk_0:
        push eax
        push ecx
        push edx

        push eax
        
        mov dx,0x1f2
        mov al,1
        out dx,al                       ; 读取的扇区数

        inc dx                          ; 0x1f3
        pop eax
        out dx,al                       ; LBA地址7～0

        inc dx                          ; 0x1f4
        mov cl,8
        shr eax,cl
        out dx,al                       ; LBA地址15～8

        inc dx                          ; 0x1f5
        shr eax,cl
        out dx,al                       ; LBA地址23～16
        
        inc dx                          ; 0x1f6
        shr eax,cl
        or al,0xe0
        out dx,al                       ; LBA地址27～24
        
        inc dx                          ; 0x1f7
        mov al,0x20                     ; 读命令 
        out dx,al

    .waits:
        in al,dx
        and al,0x88
        cmp al,0x08
        jnz .waits                      

        mov ecx,256                     ; 总共要读取的字数
        mov dx,0x1f0
    .readw:
        in ax,dx
        mov [ebx],ax
        add ebx,2
        loop .readw

        pop edx
        pop ecx
        pop eax
        
        retf                            ; 段间返回

;---------------------------------------------------------------------------

;
;在当前光标处以十六进制形式显示一个双字并推进噶光标
; @Param EDX 要转换并显示的数字
;
put_hex_dword:
        pushad
        push ds
        mov ax,core_data_seg_sel        ; 切换到核心数据段
        mov dx,ax
      
        mov ebx,bin_hex                 ; 指向核心数据段内的转换表
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
        pushad
        retf


;---------------------------------------------------------------------------
; 
; 分配内存
; @Param ECX 希望分配的字节数
; @Return ECX 起始线性地址
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
;
; 在GDT内安装一个新的描述符
; @Param EDX：EAX 描述符
; @Return CX 描述符的选择子
;
set_up_gdt_descriptor:
        push eax
        push ebx 
        push ecx
        
        push ds
        push es

        mov ebx,core_data_seg_sel                   ; 切换到核心数据段
        mov ds,ebx
            
        sgdt [pgdt]                                 ;
        
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
;
; 构造存储器和系统的段描述符
; @Param EAX 线性基地址
; @Param EBX 段界限
; @Param ECX 属性
; @Return EDX:EAX 描述符
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

; ================================================================
SECTION core_data vstart=0                          ; 系统核心的数据段
; ----------------------------------------------------------------
        pgdt        dw 0                            ; 用于设置和修改GDT
                    dd 0
        ram_alloc   dd 0x00100000                   ; 下次分配内存时的起始地址
        ; 符号地址检索表
        salt:
        salt_1          db  '@PrintString'
                    times 256-($-salt_1) db 0
                        dd  put_string
                        dw  sys_routine_seg_sel

        salt_2          db  '@ReadDiskData'
                    times 256-($-salt_2) db 0
                        dd  read_hard_disk_0
                        dw  sys_routine_seg_sel

        salt_3          db  '@PrintDwordAsHexString'
                    times 256-($-salt_3) db 0
                        dd  put_hex_dword
                        dw  sys_routine_seg_sel

        salt_4          db  '@TerminateProgram'
                    times 256-($-salt_4) db 0
                        dd  return_point
                        dw  core_code_seg_sel
        
        salt_item_len   equ $-salt_4
        salt_items      equ ($-salt)/salt_item_len
        
        message_1       db  '  If you seen this message,that means we '
                        db  'are now in protect mode,and the system '
                        db  'core is loaded,and the video display '
                        db  'routine works perfectly.',0x0d,0x0a,0

        message_5       db  '  Loading user program...',0
        
        do_status       db  'Done.',0x0d,0x0a,0
        
        message_6       db  0x0d,0x0a,0x0d,0x0a,0x0d,0x0a
                        db  '  User program terminated,control returned.',0
        
        bin_hex         db  '0123456789ABCDEF'          ; put+hex_dword 子过程用的查找表

        core_buf        times 2048 db 0                 ; 内核用的缓冲区
        
        esp_pointer     dd 0                            ; 内核用来临时保存自己的栈指针
    
        cpu_brnd0       db 0x0d,0x0a,'  ',0
        cpu_brand       times 52 db 0
        cpu_brnd1       db 0x0d,0x0a,0x0d,0x0a,0


; ===============================================================
SECTION core_code vstart=0
; ---------------------------------------------------------------

;
; 加载并重定位用户程序
; @Param    ESI 起始逻辑扇区
; @Return   AX  指向用户程序头部的选择子
;
load_relocate_program:                                  
        push ebx
        push ecx
        push edx
        push esi
        push edi

        push ds
        push es
        
        mov eax,core_data_seg_sel
        mov ds,eax                                      ; 切换DS到内核数据段
    
        mov eax,esi                                     ; 读取程序头部数据
        mov ebx,core_buf
        call sys_routine_seg_sel:read_hard_disk_0

        ; 判断程序大小
        mov eax,[core_buf]
        mov ebx,eax
        and ebx,0xfffffe00                              ; 凑整
        add ebx,512                                     ; 
        test eax,0x000001ff                             ; 程序的大小正好是512的倍数吗？ 
        cmovnz eax,ebx                                  ; 使用凑整的结果

        mov ecx,eax
        call sys_routine_seg_sel:allocate_memory
        mov ebx,ecx                                     ; 申请到的内存首地址
        push ebx                                        ; 保存该首地址
        xor edx,edx
        mov ecx,512
        div ecx
        mov ecx,eax                                     ; 总扇区数

        mov eax,mem_0_4_gb_seg_sel                      ; 切换DS到0-4G的段
        mov ds,eax
        mov eax,esi

    .b1:
        call sys_routine_seg_sel:read_hard_disk_0
        inc eax
        loop .b1        

        ; 建立程序头部段描述符
        pop edi                                         ; 恢复程序装载的首地址
        mov eax,edi                                     ; 程序头部起始线性地址
        mov ebx,[edi+0x04]                              ; 段长度
        dec ebx                                         ; 段界限
        mov ecx,0x00409200                              ; 字节粒度的数据段描述符
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [edi+0x04],cx

        ; 建立程序代码段描述符
        mov eax,edi
        add eax,[edi+0x14]                              ; 代码起始线性地址
        mov ebx,[edi+0x18]                              ; 段长度
        dec ebx
        mov ecx,0x00409800                              ; 字节粒度的代码段描述符
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [edi+0x14],cx
        
        ; 建立程序数据段描述符
        mov eax,edi
        add eax,[edi+0x1c]                              ; 数据段起始线性地址
        mov ebx,[edi+0x20]
        dec ebx
        mov ecx,0x00409200                              ; 字节粒度的数据段描述符
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [edi+0x1c],cx

        ; 建立程序堆栈段描述符
        mov ecx,[edi+0x0c]                              ; 4KB的倍率
        mov ebx,0x000fffff
        sub ebx,ecx                                     ; 得到段界限
        mov eax,4096                                    ; 4096 -> 4KB
        mul dword [edi+0x0c]
        mov ecx,eax                                     ; 准备为堆栈分配内存
        call sys_routine_seg_sel:allocate_memory
        add eax,ecx                                     ; 得到堆栈的高端物理地址
        mov ecx,0x00c09600                              ; 4KB粒度的堆栈段描述符
        call sys_routine_seg_sel:make_seg_descriptor
        call sys_routine_seg_sel:set_up_gdt_descriptor
        mov [edi+0x08],cx

        ; 重定位SALT
        mov eax,[edi+0x04]                              ; 取出刚刚安装好的头部段选择子
        mov es,eax                                      ; es -> 用户程序头部
        mov eax,core_data_seg_sel
        mov ds,eax                                      ; 指向内核数据段
        
        cld                                             ; 清除EFLAGS中的方向标志，使cmps指令按正向进行比较
        
        mov ecx,[es:0x24]                               ; 用户程序的SALT条目数
        mov edi,0x28
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

        mov ax,[es:0x04]

        pop es
        pop ds

        pop edi
        pop esi
        pop edx
        pop ecx 
        pop ebx

        ret

        

; ----------------------------------------------------------------
start:
        mov ecx,core_data_seg_sel                  ; 使ds指向核心数据段
        mov ds,ecx

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

        mov ebx,message_5
        call sys_routine_seg_sel:put_string

        mov esi,50                              ; 用户程序位于逻辑50扇区
        call load_relocate_program
        
        mov ebx,do_status
        call sys_routine_seg_sel:put_string

        mov [esp_pointer],esp                   ; 临时保存堆栈指针

        mov ds,ax

        jmp far [0x10]                          ; 控制权交给用户程序（入口点）
                                                ; 堆栈可能切换

return_point:                                   ; 用户程序返回点 
        mov eax,core_data_seg_sel               ; 使DS指向核心数据段
        mov ds,eax
        
        mov eax,core_stack_seg_sel              ; 切换回内核自己的堆栈
        mov ss,eax
        mov esp,[esp_pointer]

        mov ebx,message_6
        call sys_routine_seg_sel:put_string

        hlt

;===========================================================================
SECTION core_trail
;---------------------------------------------------------------------------
core_end:
