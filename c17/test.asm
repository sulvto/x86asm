
%macro  alloc 0
    mov ebx,[core_tcb+0x06]
    add dword [core_tcb+0x06],0x1000
    call flat_4gb_code_seg_sel:alloc_inst_a_page
                                                 
%endmacro








%macro  prologue 0
        mov ebx,[core_tcb+0x06]
        add dword [core_tcb+0x06],0x1000
        call flat_4gb_code_seg_sel:alloc_inst_a_page     
        push    ebp 
        mov     ebp,esp 
        sub     esp,[1]

%endmacro


start:
        prologue

        alloc

%macro  silly 2 

    %2: db      %1 

%endmacro 

        silly 'a', letter_a             ; letter_a:  db 'a' 
        silly 'ab', string_ab           ; string_ab: db 'ab' 
        silly {13,10}, crlf             ; crlf:      db 13,10
