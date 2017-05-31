; x86汇编语言：从实模式到保护模式

; ====================================================================
SECTION header vstart=0
        program_length  dd program_end
        
        head_len        dd header_end
        
        stack_seg       dd 0
        stack_len       dd 1

        prgentry        dd start
        code_seg        dd section.code.start
        code_len        dd code_end

        data_seg        dd section.data.start
        data_len        dd data_end

; --------------------------------------------------------------------
        ; 符号地址检索表
        salt_items          dd (header_end-salt)/256    ; #0x24

        salt:           
        PrintString         db '@PrintString'
                        times 256-($-PrintString)   db 0
        TerminateProgram    db '@TerminateProgram'
                        times 256-($-TerminateProgram)  db 0
        ReadDiskData        db '@ReadDiskData'
                        times 256-($-ReadDiskData)  db 0        

header_end:


; ===================================================================
SECTION data vstart=0
        buffer  times 1024 db 0                         ; 缓冲区
        message_1       db 0x0d,0x0a,0x0d,0x0a
                        db '********** User program is runing ********** '
                        db 0x0d,0x0a,0        
        message_2       db '  Disk data:',0x0d,0x0a,0

data_end

; ====================================================================
    [bits 32]
; ====================================================================
SECTION code vstart=0
start:
        mov eax,ds
        mov fs,eax
        
        // TODO
    

; --------------------------------------------------------------------

program_end:
