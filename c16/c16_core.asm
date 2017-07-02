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

allocate_a_4k_page:
        ; TODO
alloc_inst_a_page:
        ; TODO
create_copy_cur_pdir:
        ; TODO
terminate_current_task:
        ; TODO

sys_routine_end:

;=====================================================================
SECTION core_data vstart=0
        pgdt            dw  0               ; 用于设置和修改GDT
                        dd  0

        page_bit_map    db  ; TODO
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

fill_descriptor_in_ldt:
        ; TODO
load_relocate_program:
        ; TODO

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
        ; TODO
core_code_end:

;=====================================================================
SECTION core_trail
core_end:
