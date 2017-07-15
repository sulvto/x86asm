; x86汇编语言：从实模式到保护模式

        flat_4gb_code_seg_sel   equ 0x0008      ; 平坦模型下的4GB代码段选择子 
        flat_4gb_data_seg_sel   equ 0x0018      ; 平坦模型下的4GB数据段选择子
        idt_linear_address      equ 0x8001f000  ; 中断描述符表的线性基地址
        
;---------------------------------------------------------------------

        ; 定义宏
        %macro alloc_core_linear 0
            mov ebx [core_tcb+0x06]
            add dword [core_tcb+0x06],0x1000
            call flat_4gb_code_seg_sel:alloc_inst_a_page
        %endmacro
;---------------------------------------------------------------------
        %macro alloc_user_linear 0                             
            mov ebx [esi+0x06]
            add dword [esi+0x06],0x1000
            call flat_4gb_code_seg_sel:alloc_inst_a_page
        %endmacro
;=====================================================================
SECTION core    vstart=0x80040000
    
        ; 系统核心头部，用于加载核心程序
        core_length     dd core_end             ; 核心程序总长度   #00
        core_entry      dd start                ; 核心代码段入口点 #04


;---------------------------------------------------------------------
        [bits 32]
;---------------------------------------------------------------------
;
; 字符串显示（适用于平坦内存模型）
; @Param EBX=字符串的线性地址
; 
put_string:
        
        push ebx
        push ecx
        
        cli                                     ; 硬件操作期间，关中断
    .getc:
        mov cl,[ebx]
        or cl,cl
        jz .exit
        call put_char
        inc ebx
        jmp .getc

    .exit:
        sti                                     ; 硬件操作完毕，开放中断
        pop ecx
        pop ebx

        retf

;---------------------------------------------------------------------
; 在当前光标处显示一个字符，并推进光标。仅用于段内调用
; @Param CL=字符ASCII码
put_char:
        pushad
        
        ; 以下取当前光标位置
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
        and ebx,0x0000ffff

        cmp cl,0x0d
        jnz .put_0a
        
        mov ax,bx   
        mov bl,80
        div bl
        mul bl
        mov bx,ax
        jmp .set_cursor
        
    .put_0a:
        cmp cl ,0x0a
        jnz .put_other
        add bx,80
        jmp .roll_screen
        
    .put_other:
        shl bx,1
        mov [0x800b8000+ebx],cl
        
        shr bx,1
        inc bx

    .roll_screen:
        cmp bx,2000
        jl .set_cursor
        
        cld
        mov esi,0x800b80a0
        mov edi,0x800b8000
        mov ecx,1920
        rep movsd
        mov bx,3840
        mov ecx,80
    .cls:
        mov word [0x800b8000+ebx],0x0720
        add bx,2
        loop .cls

        mov bx,1920
    .set_cursor:
        mov dx,0x3d4
        mov al,0x0e
        out dx,al
        inc dx
        mov al,bh
        out dx,al
        dec,dx
        mov al,0x0f
        out dx,al
        inc dx
        mov al,bl
        out dx,al

        popad
        
        ret


;---------------------------------------------------------------------
;
; 从硬盘读取一个逻辑扇区（平坦模型）
; @Param EAX=逻辑扇区号
; @Param EBX=目标缓冲区线性地址
; @Return EBX=EBX+512
read_hard_disk_0:
        cli

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
        out  dx,al

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

        sti

        retf

;---------------------------------------------------------------------
; 
;
;
put_hax_dword:
        pushad
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

        popad

        retf    

;---------------------------------------------------------------------
; 在GDT内安装一个新的描述符
; @Param EDX：EAX = 描述符
; @Retuen CX=描述符的选择子
set_up_gdt_descriptor:
        push eax
        push ebx
        push edx
        
        sgdt [pgdt]                         ; 取GDTR的界限和线性地址

        movzx ebx,word [pgdt]               ; GDT界限
        inc bx
        add ebx,[pgdt+2]                    ; 新的描述符的线性地址
    
        mov [ebx],eax
        mov [ebx+4],edx

        add word [pgdt],8                   
        
        lgdt [pgdt]
        
        mov ax,[pgdt]
        xor dx,dx
        mov bx,8
        div bx
        mov cx,ax
        shl cx,3
        
        pop edx
        pop ebx
        pop eax

        retf
    
;---------------------------------------------------------------------
; 构造存储器和系统的段描述符
; @Param EAX = 线性基地址
; @Param EBX = 段界限
; @Param ECX = 属性 各属性位都在原始位置，无关的位清零
; @Return EDX:EAX = 描述符
;
make_seg_descriptor:
        mov edx,eax
        shl eax,16
        or ax,bx                        ; 描述符前32位（EAX）Done.
        
        and edx,0xffff0000
        rol edx,8
        bswap edx
        
        xor bx,bx
        or edx,ebx                      
        
        or edx,ecx                      

        retf

;---------------------------------------------------------------------
; 构造门的描述符
; @Param EAX=门代码在段内偏移地址
; @Param BX = 门代码所在段的选择子
; @Param CX = 段类型及属性等（各属性位都在原始位置）
; @Return EDX：EAX = 完整的描述符
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
; @Return EAX = 页的物理地址
;
allocate_a_4k_page:
        push ebx
        push ecx
        push edx

        xor eax,eax
    .b1:
        bts [page_bit_map],eax
        jnc .b2
        inc eax
        cmp eax,page_map_len*8
        jl .b1
        
        mov ebx,message_3
        call flat_4gb_code_seg_sel:   put_string
        hlt                     ; 没有可分配的页

    .b2:
        shl,12

        pop edx
        pop ecx
        pop ebx
                
        ret
;---------------------------------------------------------------------
; 分配一个页，并安装到当前活动的层级分页结构中
; @Param EBX = 页的线性地址 
;
alloc_inst_a_page:
        push eax
        push ebx    
        push esi
        
        ; 检查该线性地址所对应的页表是否存在
        mov esi,ebx
        ; 1111111111 0000000000 000000000000
        and esi,0xffc00000
        shr esi,20  
        ; 11111111111111111111 000000000000
        or esi,0xfffff000                   ; 页目录
        
        test dword [esi],0x00000001         ; P位是否为'1',检查该线性地址是否已经有对应的页表
        jnz .b1
        
        ; 创建该线性地址所对应的页表
        call allocate_a_4k_page             ; 分配一个页作为页表
        ; 111
        or eax,0x00000007
        mov [esi],eax                       ; 在页目录中登记该页表
        
    .b1:
        ; 开始访问该线性地址所对应的页表
        mov esi,ebx
        shr esi,10
        ; 0000000000 1111111111 000000000000
        and esi,0x003ff000
        ; 1111111111 0000000000 000000000000
        or esi,0xffc00000
    
        ; 得到该线性地址在页表内的对应条目（页表项）
        and ebx,0x003ff000
        shr ebx,10
        or esi,ebx
        call allocate_a_4k_page             ; 分配一个页
        or eax,0x00000007
        mov [esi],eax

        pop esi
        pop ebx
        pop eax
        
        retf
           

;-------------------------------------------------------------------
; 创建新页目录，并复制当前页目录内容
; @Return EAX=新页目录的物理地址
create_copy_cur_pdir:
        push esi
        push edi
        push ebx
        push ecx

        call allocate_a_4k_page
        mov ebx,eax
        or ebx,0x00000007
        mov [0xfffffff8],ebx
        
        invlpg [0xfffffff8]
        
        mov esi,0xfffff000
        mov edi,0xffffe000
        mov ecx,1024
        cld
        repe movsd
        
        pop ecx
        pop ebx
        pop edi
        pop esi
    
        retf

;---------------------------------------------------------------------
; 通用的中断处理过程
general_interrupt_handler:
        push eax                                                 
        
        mov al,0x20                     ; 中断结束命令EOI
        out 0xa0,al                     ; 向从片发送
        out 0x20,al;                    ; 向主片发送
                                                          
        pop eax
        
        iretd                             
;---------------------------------------------------------------------
; 通用的异常处理过程
general_exception_handler:
        mov ebx,excep_msg
        call flat_4gb_code_seg_sel:put_string
    
        hlt   
        
;---------------------------------------------------------------------
; 实时时钟中断处理过程
rtm_0x70_interrupt_handle:
        pushad
        
        mov al,0x20                     ; 中断结束命令EOI
        out 0xa0,al                     ; 向8259A从片发送
        out 0x20,al                     ; 向8259A主片发送

        mov al,0x0c                     ; 寄存器C的索引
        out 0x70,al     
        in al,0x71                      ; 读下一个RTC的寄存器C，
                                        ; 否则只发生一次中断
                                        ; 不考虑闹钟和周期性中断的情况

        ; 找到当前任务(状态为忙的任务)在链表中的位置
        mov eax,tcb_chain
    .b0:
        mov ebx,[eax]
        or ebx,ebx
        jz .irtn
        cmp word [ebx+0x04],0xffff
        je .b1
        mov eax,ebx
        jmp .b0
        
        ; 将当前为忙的任务移到链尾
    .b1:
        mov ecx,[ebx]
        mov [eax],ecx                   ; 将当前任务从链中拆除
    .b2:                                ; EBX=当前任务的线性地址
        mov edx,[eax]
        or edx,edx                      ; 链尾？
        jz .b3
        mov eax,edx
        jmp .b2

    .b3:
        mov [eax],ebx                   ; 当前任务挂到链尾
        mov dword [ebx],0x00000000
        
        ; 从链首搜索第一个空闲任务
        mov eax,tcb_chain
    .b4:
        mov eax,[eax]
        or eax,eax                  
        jz .irtn                        ; 未发现空闲任务，从中断返回
        cmp dword [eax+0x04],0x0000     ; 空闲任务？
        jnz .b4
        
        ; 将空闲任务和当前任务的状态都取反
        not word [eax,0x04]             ; 设置空闲任务的状态为忙
        not word [ebx+0x04]             ; 设置当前任务（忙）的状态为闲
        jmp far [eax+0x14]              ; 任务切换
    .irtn:
        popad
    
        iretd

;---------------------------------------------------------------------
; 终止当前任务
; 
terminate_current_task:
        ; 找当前任务在链表中的位置
        mov eax,tcb_chain
    .b0:                                ; 链表头或当前TCB线性地址
        mov ebx,[eax]                   ; EBX=下一个TCB线性地址
        cmp word [ebx+0x04],0xffff      ; 是忙任务？ 
        je .b1
        mov eax,ebx                     ; 下一个TCB线性地址
        jmp .b0
    .b1:
        mov word [ebx+0x04],0x3333      ; 修改当前任务的状态
    .b2:
        hlt                             ; 停机，等待程序管理器恢复运行
                                        ; 将其回收
    
        jmp .b2

;---------------------------------------------------------------------
        pgdt        dw  0               ; 用于设置和修改GDT
                    dd  0

        pidt        dw  0
                    dd  0
        
        ; 任务控制块链
        tcb_chain   dd  0

        core_tcb  times 32 db 0         ; 内核（程序管理器）的TCB
        
        page_bit_map     db  0xff,0xff,0xff,0xff,0xff,0xff,0x55,0x55
                          db  0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                          db  0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                          db  0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                          db  0x55,0x55,0x55,0x55,0x55,0x55,0x55,0x55
                          db  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
                          db  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
                          db  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
         page_map_len     equ $-page_bit_map
                          
         ;符号地址检索表
         salt:
         salt_1           db  '@PrintString'
                     times 256-($-salt_1) db 0
                          dd  put_string
                          dw  flat_4gb_code_seg_sel

         salt_2           db  '@ReadDiskData'
                     times 256-($-salt_2) db 0
                          dd  read_hard_disk_0
                          dw  flat_4gb_code_seg_sel

         salt_3           db  '@PrintDwordAsHexString'
                     times 256-($-salt_3) db 0
                          dd  put_hex_dword
                          dw  flat_4gb_code_seg_sel

         salt_4           db  '@TerminateProgram'
                     times 256-($-salt_4) db 0
                          dd  terminate_current_task
                          dw  flat_4gb_code_seg_sel

         salt_item_len   equ $-salt_4
         salt_items      equ ($-salt)/salt_item_len

         excep_msg        db  '********Exception encounted********',0

         message_0        db  '  Working in system core with protection '
                          db  'and paging are all enabled.System core is mapped '
                          db  'to address 0x80000000.',0x0d,0x0a,0

         message_1        db  '  System wide CALL-GATE mounted.',0x0d,0x0a,0
         
         message_3        db  '********No more pages********',0
         
         core_msg0        db  '  System core task running!',0x0d,0x0a,0
         
         bin_hex          db '0123456789ABCDEF'
                                            ;put_hex_dword子过程用的查找表 

         core_buf   times 512 db 0          ;内核用的缓冲区

         cpu_brnd0        db 0x0d,0x0a,'  ',0
         cpu_brand  times 52 db 0
         cpu_brnd1        db 0x0d,0x0a,0x0d,0x0a,0


;---------------------------------------------------------------------
; @Param EDX:EAX = 描述符
; @Param EBX=TCB基地址
; @Return CX = 描述符的选择子
fill_descriptor_in_ldt:
        push eax
        push edx
        push edi
    
        mov edi,[ebx+0x0c]                  ; LDT基地址
            
        xor ecx,ecx
        mov cx,[ebx+0x0a]                   ; LDT界限
    
        inc cx                              ; 新描述符偏移地址

        mov [edi+ecx+0x00],eax
        mov [edi+ecx+0x04],edx

        add cx,8

        dec cx

        mov [ebx+0x0a],cx                   ; 更新LDT界限值到TCB

        mov ax,cx
        xor dx,dx
        mov cx,8
        div cx

            mov cx,ax
        shl cx,3
        or cx,0000_0000_0000_0100B

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
    
        mov ebp,esp                     ; 为访问通过堆栈传递的参数做准备
        
        ; 清空当前目录的前半部分(对应低2GB的局部地址空间)
        mov ebx,0xfffff000
        xor esi,esi
    .b1:
        mov dword [ebx+esi*4],0x00000000
        inc esi
        cmp esi,512
        jl .b1
    
        mov eax,cr3
        mov cr3,eax                     ;刷新TLB
        
        ; 分配内存并加载用户程序
        mov eax [ebp+40]                ; 起始扇区号
        mov ebx,core_buf
        call flat_4gb_code_seg_sel:read_hard_disk_0

        ; 判断整个程序有多大
        mov eax,[core_buf]
        mov ebx,eax
        and ebx,0xfffff000
        add ebx,0x1000  
        test eax,0x00000fff
        cmovnz eax,ebx
        
        mov ecx,eax
        shr ecx,12

        mov eax,[ebp+40]                ; 起始扇区号
        mov esi,[ebp+36]                ; TCB的基地址

    .b2:
        alloc_user_linear
        
        push ecx
        mov ecx,8
    .b3:
        call flat_4gb_code_seg_sel:read_hard_disk_0
        inc eax
        loop .b3

        pop ecx     
        loop .b2

        alloc_core_linear
        
        mov [esi+0x14],ebx
        mov word [esi+0x12],103
        
        alloc_user_linear

        mov [esi+0x0c],ebx

        ; 建立程序代码段描述符
        mov eax,0x00000000
        mov ebx,0x000fffff
        mov ecx,0x00c0f800  
        call flat_4gb_code_seg_sel:make_seg_descriptor
        mov ebx,esi
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B
        
        mov ebx,[esi+0x14]              ; TCB中获取TSS的线性地址
        mov [ebx+76],cx                 ; 填写TSS的CS域

       
        ; 建立程序数据段描述符
        mov eax,0x00000000
        mov ebx,0x000fffff
        mov ecx,0x00c0f200  
        call flat_4gb_code_seg_sel:make_seg_descriptor
        mov ebx,esi
        call fill_descriptor_in_ldt
        or cx,0000_0000_0000_0011B
                
        mov ebx,[esi+0x14]              ; TCB中获取TSS的线性地址
        mov [ebx+84],cx                 ; 填写TSS的DS域
        mov [ebx+72],cx                 ; 填写TSS的ES域
        mov [ebx+88],cx                 ; 填写TSS的FS域
        mov [ebx+92],cx                 ; 填写TSS的GS域
 
        ; 将数据段作为用户程序的3特权级固有堆栈
        alloc_user_linear

        mov ebx,[esi+0x14]              ; TCB中获取TSS的线性地址
        mov [ebx+80],cx                 ; 填写TSS的SS域
        mov edx,[esi+0x06]              ; 堆栈的高端线性地址
        mov [ebx+56],edx                ; 填写TSS的ESP域
        
        ;在用户程序的局部地址空间内创建0特权级堆栈
        alloc_user_linear
        
        mov eax,0x00000000
        mov ebx,0x000fffff
        mov ecx,0x00c09200              ; 4KB粒度的堆栈段描述符，特权级0
        call flat_4gb_code_seg_sel:make_seg_descriptor
        mov ebx,esi                     ; TCB的基地址
        call fill_descriptor_in_ldt     
        or cx,0000_0000_0000_0000B      ; 设置选择子的特权级为0
        
        mov ebx,[esi+0x14]              ; 从TCB中获取TSS的线性地址
        mov [ebx+8],cx                  ; 填写TSS的SS0域
        mov edx,[esi+0x06]              ; 堆栈的高端线性地址
        mov [ebx+4],edx                 ; 填写TSS的ESP0域

        ;在用户程序的局部地址空间内创建1特权级堆栈
        alloc_user_linear
        
        mov eax,0x00000000
        mov ebx,0x000fffff
        mov ecx,0x00c0b200              ; 4KB粒度的堆栈段描述符，特权级1
        call flat_4gb_code_seg_sel:make_seg_descriptor
        mov ebx,esi                     ; TCB的基地址
        call fill_descriptor_in_ldt     
        or cx,0000_0000_0000_0001B      ; 设置选择子的特权级为1
        
        mov ebx,[esi+0x14]              ; 从TCB中获取TSS的线性地址
        mov [ebx+16],cx                 ; 填写TSS的SS1域
        mov edx,[esi+0x06]              ; 堆栈的高端线性地址
        mov [ebx+12],edx                ; 填写TSS的ESP1域

        ;在用户程序的局部地址空间内创建0特权级堆栈
        alloc_user_linear
        
        mov eax,0x00000000
        mov ebx,0x000fffff
        mov ecx,0x00c0d200              ; 4KB粒度的堆栈段描述符，特权级2
        call flat_4gb_code_seg_sel:make_seg_descriptor
        mov ebx,esi                     ; TCB的基地址
        call fill_descriptor_in_ldt     
        or cx,0000_0000_0000_0010B      ; 设置选择子的特权级为2
        
        mov ebx,[esi+0x14]              ; 从TCB中获取TSS的线性地址
        mov [ebx+24],cx                 ; 填写TSS的SS2域
        mov edx,[esi+0x06]              ; 堆栈的高端线性地址
        mov [ebx+20],edx                ; 填写TSS的ESP2域

        ; 重定位U-SALT
        cld

        mov ecx,[0x0c]                  ; U-SALT条目数
        mov edi,[0x08]                  ; U-SALT在4GB空间内的偏移
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
        repe cmped
        jnz .b6
        mov eax,[esi]
        mov [edi-256],eax
        mov ax,[esi+4]
        or ax,0000000000000011B

        mov [edi-252],ax
    .b6:
        
        pop ecx
        pop esi
        add esi,salt_item_len
        pop edi
        loop .b5

        pop edi
        add edi,256
        pop ecx
        loop .b4

        ; 在GDT中登记LDT描述符  
        mov esi,[ebp+36]
        mov eax,[esi+0x0c]
        movzx ebx,word [esi+0x0a]
        mov ecx,0x00408200
        call flat_4gb_code_seg_sel:make_seg_descriptor
        call flat_4gb_code_seg_sel:set_up_gdt_descriptor
        mov [esi+0x10],cx
        
        mov ebx,[esi+0x14]
        mov [ebx+96],cx
        
        mov word [ebx+0],0

        mov dx,[esi+0x12]
        mov [ebx+102],dx
    
        mov word [ebx+100],0

        mov eax,[0x04]
        mov [ebx+32],eax
    
        pushfd
        pop edx
        mov [ebx+36],edx

        ; 在GDT中登记TSS描述符
        mov eax,[esi+0x14]                  ; TCB中TSS的起始地址
        movzx ebx,word [esi+0x12]
        mov ecx,0x00408900
        call flat_4gb_code_seg_sel:make_seg_descriptor
        call flat_4gb_code_seg_sel:set_up_gdt_descriptor
        mov [esi+0x18],cx

        call flat_4gb_code_seg_sel:create_copy_cur_pdir
        mov ebx,[esi+0x14]
        mov dword [ebx+28],eax

        popad

        ret 8 

;---------------------------------------------------------------------
; 在TCB链上追加任务控制块
; @Param ECX=TCB线性基地址
append_to_tcb_link:
        cli
        push eax
        push ebx
        mov eax,tcb_chain
    .b0:
        mov ebx,[eax]
        or ebx,ebx
        jz .b1
        mov eax,ebx
        jmp .b0
    .b1:
        mov [eax],ecx
        mov dword [ecx],0x00000000      ; 当前TCB指针域清零，以指示这是最后一个TCB
        pop ebx
        pop eax

        sti
        
        ret

        
;---------------------------------------------------------------------
start:
        ; 创建中断描述表IDT
        ; 前20个向量是处理器异常使用                    
        mov eax,general_exception_handler           ; 门代码在段内偏移地址
        mov bx,flat_4gb_code_seg_sel                ; 门代码所在段的选择子
        mov cx,0x8e00                               ; 32位中断门，0特权级 
        call flat_4gb_code_seg_sel:make_gate_descriptor        

        mov ebx,idt_linear_address                  ; 中断描述表的线性地址
        xor esi,esi
    .idt0:
        mov [ebx+esi*8],eax
        mov [ebx+esi*8+4],edx
        inc esi
        cmp esi,19                                  ; 安装前20个异常中断处理过程
        jle .idt0

        ; 其余为保留或硬件使用的中断向量
        mov eax,general_interrupt_handler           ; 门代码在段内偏移地址
        mov bx,flat_4gb_code_seg_sel                ; 门代码所在段的选择子
        mov cx,0x8e00                               ; 32位中断门，0特权级 
        call flat_4gb_code_seg_sel:make_gate_descriptor
        
        mov ebx,idt_linear_address                  ; 中断描述表的线性地址
    .idt1:
        mov [ebx+esi*8],eax
        mov [ebx+esi*8+4],edx
        inc esi 
        cmp esi,255                                 ; 安装普通的中断处理过程
        jle .idt1

        ; 设置实时时钟中断处理过程
        mov eax,rtm_0x70_interrupt_handle           ; 门代码在段内偏移地址
        mov bx,flat_4gb_code_seg_sel                ; 门代码所在段的选择子
        mov cx,0x8e00                               ; 32位中断门，0特权级
        call flat_4gb_code_seg_sel:make_gate_descriptor

        mov ebx,idt_linear_address                  ; 中断描述表的线性地址
        mov [ebx+0x70*8],eax
        mov [ebx+0x70*8+4],edx

        ; 准备开放中断
        mov word [pidt],256*8-1                     ; IDT的界限
        mov dword [pidt+2],idt_linear_address
        lidt    [pidt]                              ; 加载中断描述符表寄存器IDTR

        ; 设置8259A中断控制器
        mov al,0x11
        out 0x20,al                                 ; ICW1:边沿触发/级联方式
        mov al,0x20
        out 0x21,al                                 ; ICW2:起始中断向量
        mov al,0x04     
        out 0x21,al                                 ; ICW3:从片级联到IR2
        mov al,0x01
        out 0x21,al                                 ; ICW4:非总线缓冲,全嵌套，正常EOI

        mov al,0x11
        out 0xa0,al                                 ; ICW1:边沿触发/级联方式
        mov al,0x70                                                                   
        out 0xa1,al                                 ; ICW2:起始中断向量
        mov al,0x04                                                                   
        out 0xa1,al                                 ; ICW3:从片级联到IR2
        mov al,0x01                                                                   
        out 0xa1,al                                 ; ICW4:非总线缓冲,全嵌套，正常EOI
        
        ; 设置和时钟中断相关的硬件
        mov al,0x0b                                 ; RTC寄存器B
        ; 0x80 10000000
        or al,0x80                                  ; 阻断NMI
        out 0x70,al
        mov al,0x12                                 ; 设置寄存器B，禁止周期性中断，开放
        out 0x70,al                                 ; 更新结束后中断，BCD码，24小时制

        in al,0x21                                  ; 读8259从片的IMR寄存器
        ; 11111110
        and al,0xfe                                 ; 清除bit 0（此位连接RTC）
        out 0xa1,al                                 ; 写回此寄存器

        mov al,0x0c
        out 0x70,al
        in al,0x71                                  ; 读RTC寄存器C，复位未决的中断状态
        
        sti                                         ; 开放硬件中断

        mov ebx,message_0
        call flat_4gb_code_seg_sel:put_string

        ;显示处理器品牌信息
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
        call flat_4gb_code_seg_sel:put_string
        mov ebx,cpu_brand
        call flat_4gb_code_seg_sel:put_string
        mov ebx,cpu_brnd1
        call flat_4gb_code_seg_sel:put_string

        ; 安装为整个系统服务的调用门。特权级之间的控制转移必须使用门
        mov edi,salt
        mov ecx,salt_items
    .b4:
        push ecx
        mov eax,[edi+256]
        mov bx,[edi+260]
        mov cx,1_11_0_1100_000_00000B
        
        call flat_4gb_code_seg_sel：make_gate_descriptor
        call flat_4gb_code_seg_sel:set_up_gdt_descriptor
        mov [edi+260],cx
        add edi,salt_item_len
        pop ecx
        loop .b4

        ; 对门进行测试
        mov ebx,message_1
        call far [salt_1+256]

        ; 初始化创建任务管理器任务的任务控制块TCB
        mov word [core_tcb+0x04],0xffff                 ; 任务状态：忙碌
        mov dword [core_tcb+0x06],0x80100000            ; 
        
        mov word [core_tcb+0x0a],0xffff                 ; 登记LDT初始的界限到TCB中（未使用）
        mov ecx,core_tcb
        call append_to_tcb_link

        ; 为程序管理器的TSS分配内存空间
        alloc_core_linear

        ; 在程序管理器的TSS中设置必要的项目
        mov word [ebx+0],0                              ; 反向链=0
        mov eax,cr3
        mov dword [ebx+28],eax                          ; 登记CR3（PDBR）
        mov word [ebx+96],0                             ; 没有LDT。处理器允许没有LDT的任务
        mov word [ebx+100],0                            ; T=0
        mov word [ebx+102],103                          ; 没有I/O。0特权级事实上不需要

        ; 创建程序管理器的TSS描述符，并安装到GDT中
        mov eax,ebx
        mov ebx,103
        mov ecx,0x00408900
        call flat_4gb_code_seg_sel:make_seg_descriptor
        call flat_4gb_code_seg_sel:set_up_gdt_descriptor
        mov [core_tcb+0x18],cx
        
        
        ltr cx
        
        alloc_core_linear
        
        mov word [ebx+0x04],0
        mov dwoord [ebx+0x06],0
        mov word [ebx+0x0a],0xffff
    
        push dword 50
        push ebx
        call load_relocate_program
        mov ecx,ebx
        call append_to_tcb_link

        alloc_core_linear

        mov word [ebx+0x04],0
        mov dwoord [ebx+0x06],0
        mov word [ebx+0x0a],0xffff
                                   
        push dword 100
        push ebx
        call load_relocate_program
        mov ecx,ebx
        call append_to_tcb_link

    .core:
        mov ebx,core_msg0
        call flat_4gb_code_seg_sel:put_string
        
        jmp .core




    
core_code_end:

;---------------------------------------------------------------------
SECTION core_trail
;---------------------------------------------------------------------
core_end:
