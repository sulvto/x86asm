; x86汇编语言：从实模式到保护模式

; 常量
core_code_seg_sel   equ 0x38    ; 内核代码段选择子
core_data_seg_sel   equ 0x30    ; 内核数据段选择子
sys_routine_seg_sel equ 0x28    ; 系统公共例程代码段选择子




; ================================================================
    [bit 32]
; ================================================================
SECTION sys_routine vstart=0                       ; 系统公共例程代码段
; ----------------------------------------------------------------

;
;字符串显示
;
put_string:
        put ecx
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
put_chat:
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
        inc dx
        in al,dx
        inc dx                  ; 0x3d5
        in al,dx                ; 低字
        mov bx,ax               

        cmp cl,0x0d             ; 回车符？
        jzp  .put_0a
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
        cmp bc,2000
        jl .set_cursor

        push ds
        push es
        mov eax,video_ram_seg_sel
        mov de,eax
        mov es,eax
        cld
        // TODO


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
                        dd  read_hard_disk_0
                        dw  sys_routine_seg_sel

        salt_4          db  '@TerminateProgram'
                    times 256-($-salt_4) db 0
                        dd  retrun_point
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
      // TODO

  
; ----------------------------------------------------------------
start:
        mov ecx core_data_seg_sel                  ; 使ds指向核心数据段
        mov ds,ecx

        mov sbx,message_1
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

return_point:
        // TODO


