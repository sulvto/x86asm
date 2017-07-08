; x86汇编语言：从实模式到保护模式

        program_len     dd  program_end                 ; 0x00
        entry_point     dd  start                       ; 0x04
        salt_position   dd  salt_begin                  ; 0x08
        salt_items      dd  (salt_end-salt_begin)/256   ; 0x0c


        salt_begin:
        PringString     db  '@PringString'
                    times   256-($-PringString) db 0
        
        TerminateProgram db '@TerminateProgram'
                    times   256-($-TerminateProgram) db 0

;---------------------------------------------------------------------
        reserved    times 256*500 db 0
;---------------------------------------------------------------------

        ReadDiskData    db '@ReadDiskData'
                    times 256-($-ReadDiskData) db 0
    
        PrintDWordAsHex db '@PrintDWordAsHexString'
                    times 256-($-PrintDWordAsHex) db 0

        
        salt_end:
        message_0       db  0x0d,0x0a
                        db  '   ............User task is running with '
                        db  'paging enable........',0x0d,0x0a,0

        space           db 0x20,0x20,0
    
;--------------------------------------------------------------------

        [bits 32]

start:
        mov eax,message_0
        call far  [PringString]
    
        xor esi,esi

        mov ecx,88

    .b1:
        mov ebx,space
        call far [PringString]

        mov edx,[esi*4]
        call far [PrintDWordAsHex]

        inc esi
        loop .b1

        inc esi
        loop .b1
        
        call far [TerminateProgram]
;---------------------------------------------------------------------
program_end:
