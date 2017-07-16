; x86汇编语言：从实模式到保护模式
        program_len     dd  program_end
        entry_point     dd  start
        salt_position   dd  salt_begin
        salt_items      dd  (salt_end-salt_begin)/256

;---------------------------------------------------------------------

        salt_begin:
        PrintString     db  '@PrintString'
                    times 256-($-PrintString) db 0

        TerminateProgram     db  '@TerminateProgram'
                    times 256-($-TerminateProgram) db 0

        ReadDiskData     db  '@ReadDiskData'
                    times 256-($-ReadDiskData) db 0


        PrintDWordAsHex     db  '@PrintDWordAsHex'
                    times 256-($-PrintDWordAsHex) db 0

        salt_end:

        message_0           db  '   User task b->;;;;;;;;;;;;;;;;;;;'
                            db  0x0d,0x0a,0

;---------------------------------------------------------------------

        [bits 32]

;---------------------------------------------------------------------

start:
        mov ebx,message_0
        call far [PrintString]
        jmp start
        
        call far [TerminateProgram]

;---------------------------------------------------------------------
program_end:






