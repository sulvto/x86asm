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
                                            
        ; TODO



;---------------------------------------------------------------------
SECTION core_trail
;---------------------------------------------------------------------

core_end:
        
