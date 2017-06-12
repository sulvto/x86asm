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
put_string:
        ; TODO

put_char:
        ; TODO

read_hard_disk_0:
        ; TODO

put_hex_dword:
        ; TODO

allocate_memory:
        ; TODO

set_up_gdt_descriptor:
        ; TODO

make_seg_descriptor:
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
load_relocate_program:
    ; TODO
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

        push dword [0x08]
        push dword 0
        push dword [0x14]
        push dword [0x10]
        
        retf

return_point:
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