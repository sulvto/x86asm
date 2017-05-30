; x86汇编语言：从实模式到保护模式

;=====================================================================
SECTION header vstart=0                     ; 定义用户程序头部段
    program_len     dd program_end          ; 程序总长度 [0x00]
    
    ; 用户程序入口点
    code_entry      dw start                ; 偏移地址   [0x04]
                    dd section.code_1.start ; 段地址     [0x06]
    
    ; 段重定位表项个数 5...
    realloc_tbl_len dw (header_end-code_1_seg)/4        ;[0x0a]  

    ; 段重定位表
    code_1_seg      dd section.code_1.start             ;[0x0c]
    code_2_seg      dd section.code_2.start             ;[0x10]
    data_1_seg      dd section.data_1.start             ;[0x14]
    data_2_seg      dd section.data_2.start             ;[0x18]
    stack_seg       dd section.stack.start              ;[0x1c]
    
    header_end:

;=====================================================================
SECTION code_1 align=16 vstart=0

;
; 显示字符串
; @Param DS:BX 串地址
;
put_string:
        mov cl,[bx]
        or cl,cl                                ; cl=0 ?
        jz .exit
        call put_char
        inc bx
        jmp put_string

    .exit:
        ret

;---------------------------------------------------------------------
;
; 显示字符
; @Param cl 字符ascii
;
put_char:
        push ax
        push bx
        push cx
        push dx
        push ds
        push ss
        
        ; 取当前光标位置
        mov dx,0x3d4    
        mov al,0x0e
        out dx,al
        mov dx,0x3d5
        in al,dx                        ; 高8位
        mov ah,al
        
        mov dx,0x3d4
        mov al,0x0f
        out dx,al
        mov dx,0x3d5
        in al,dx                        ; 低8位
        mov bx,ax                       ; 

        cmp cl,0x0d                     ; 回车符？
        jnz .put_0a
        mov ax,bx
        mov bl,80
        div bl
        mul bl
        mov bx,ax
        jmp .set_cursor
    
    .put_0a:
        cmp cl,0x0a                     ; 换行符？
        jnz .put_other
        add bx,80
        jmp .roll_screen

    .put_other:                         ; 正常显示字符
        mov ax,0xb800
        mov es,ax
        shl bx,1
        mov [es:bx],cl

        ; 将光标位置推进一个字符
        shr bx,1
        add bx,1
        
    .roll_screen:
        cmp bx,2000                     ; 光标超出屏幕？
        jl .set_cursor

        mov ax,0xb800
        mov ds,ax
        mov es,ax
        cld
        mov si,0xa0
        mov di,0x00
        mov cx,1920
        rep movsw
        mov bx,3840                     ; 清除屏幕最底一行      
        mov cx,80
         
    .cls:
        mov word [es:bx],0x0720
        add bx,2
        loop .cls
            
        mov bx,1920

    .set_cursor:
        mov dx,0x3d4
        mov al,0x0e
        out dx,al
        mov dx,0x3d5
        mov al,bh
        out dx,al
        mov dx,0x3d4
        mov al,0x0f
        out dx,al
        mov dx,0x3d5
        mov al,bl
        out dx,al
    
        pop es
        pop ds
        pop dx
        pop cx
        pop bx
        pop ax
        
        ret

;---------------------------------------------------------------------

start:
        ; 初始执行时，DS和ES指向用户程序头部段
        mov ax,[stack_seg]                  ; 设置到用户程序自己的堆栈
        mov ss,ax
        mov sp,start_end

        mov ax,[data_1_seg]                 ; 设置到用户程序自己的数据段
        mov ds,ax
        
        mov bx,msg0
        call put_string                     ; 显示第一段信息

        push word [es:code_2_seg]
        mov ax,begin
        push ax

        retf

continue:
        mov ax,[es:data_2_seg]              ; 段寄存器DS切换到数据段2
        mov ds,ax

        mov bx,msg1
        call put_string                     ; 显示第二段信息
        
        jmp $

;=====================================================================
SECTION code_2 align=16 vstart=0
    
    begin:
        push word [es:code_1_seg]
        mov ax,continue
        push ax

        retf                                ; 转移到代码段1接着执行

;=====================================================================
SECTION data_1 align=16 vstart=0
    msg0 db ' This is NASM - the famous Netwide Assembler. '
         db 'Back at SourceForge and in intensive development! '
         db 'Get the corrent versions form http://www.nasm.us/.'
         db 0x0d,0x0a,0x0d,0x0a
         db '  Example code for calculate 1+2+...+1000:',0x0d,0x0a,0x0d,0x0a
         db '     xor dx,dx',0x0d,0x0a
         db '     xor ax,ax',0x0d,0x0a
         db '     xor cx,cx',0x0d,0x0a
         db '  @@:',0x0d,0x0a
         db '     inc cx',0x0d,0x0a
         db '     add ax,cx',0x0d,0x0a
         db '     adc dx,0',0x0d,0x0a
         db '     inc cx',0x0d,0x0a
         db '     cmp cx,1000',0x0d,0x0a
         db '     jle @@',0x0d,0x0a
         db '     ... ...(Some other codes)',0x0d,0x0a,0x0d,0x0a
         db 0

;=====================================================================

SECTION data_2 align=16 vstart=0
    msg1 db '  The above contents is written by LeeChung. '
         db '2017-05-30'
         db 0

;=====================================================================

SECTION stack align=16 vstart=0
    resb 256
start_end:

;=====================================================================
SECTION trail align=16
program_end:
