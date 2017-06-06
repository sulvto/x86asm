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
    
        ; TODO
       





