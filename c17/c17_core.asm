; x86汇编语言：从实模式到保护模式

        flat_4gb_code_seg_sel   equ 0x0008      ; 平坦模型下的4GB代码段选择子 
        flat_4gb_data_seg_sel   equ 0x0018      ; 平坦模型下的4GB数据段选择子
        idt_linear_address      equ 0x8001f000  ; 中断描述符表的线性基地址
        
;---------------------------------------------------------------------




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
        ; TODO
;---------------------------------------------------------------------
; 在当前光标处显示一个字符，并推进光标。仅用于段内调用
; @Param CL=字符ASCII码
put_char:
        ; TODO

;---------------------------------------------------------------------
;
; 从硬盘读取一个逻辑扇区（平坦模型）
; @Param EAX=逻辑扇区号
; @Param EBX=目标缓冲区线性地址
; @Return EBX=EBX+512
read_hard_disk_0:
        ; TODO

;---------------------------------------------------------------------
put_hax_dword:
        ; TODO

;---------------------------------------------------------------------
set_up_gdt_descriptor:
        ; TODO
    
;---------------------------------------------------------------------
make_seg_descriptor:
        ; TODO

;---------------------------------------------------------------------
make_gate_descriptor:
        ; TODO
;---------------------------------------------------------------------
allocate_a_4k_page:
        ; TODO
;---------------------------------------------------------------------
alloc_inst_a_page:
        ; TODO
;---------------------------------------------------------------------
create_copy_cur_pdir:
        ; TODO

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
terminate_current_task:
        ; TODO

;---------------------------------------------------------------------
        pgdt        dw  0               ; 用于设置和修改GDT
                    dd  0

        pidt        dw  0
                    dd  0
        
        ; 任务控制块链
        tcb_chain   dd  0

        core_tcb  times 32 db 0         ; 内核（程序管理器）的TCB
        ; TODO
;---------------------------------------------------------------------
fill_descriptor_in_ldt:
        ; TODO
;---------------------------------------------------------------------
load_relocate_program:
        ; TODO
;---------------------------------------------------------------------
append_to_tcb_link:
        ; TODO
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
        out 0x20,al                                 ; ICW1:边缘
        mov al,0x20
        out 0x21,al
        mov al,0x04
        out 0x21,al
        mov al,0x01
        out 0x21,al

        mov al,0x11
        out 0xa0,al
        mov al,0x70
        out 0xa1,al
        mov al,0x04
        out 0xa1,al 
        mov al,0x01
        out 0xa1,al
        ; TODO
;---------------------------------------------------------------------
SECTION core_trail
;---------------------------------------------------------------------
core_end:
