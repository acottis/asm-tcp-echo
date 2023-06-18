[BITS 64]
DEFAULT REL
global entry

; How to call windows x64
; https://github.com/simon-whitehead/assembly-fun/blob/master/windows-x64/README.md
; https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention?view=msvc-170

; Optional feature
%define LOGGING

extern WSAStartup
extern ExitProcess
extern getaddrinfo
extern socket
extern bind
extern listen
extern accept
extern recv
extern send
extern closesocket
%ifdef LOGGING
    extern GetStdHandle
    extern WriteConsoleA
    extern SetConsoleTextAttribute
    extern GetLocalTime
%endif

%define WIN64_STACK_SHADOW_THINGY 0x28
%define VERSION_2_2 WORD 0x0202
%define AF_UNSPEC DWORD 0x00
%define SOCK_STREAM DWORD 0x01
%define IPPROTO_TCP DWORD 0x06
%define SOMAXCONN DWORD 0x7fffffff
%define RECV_BUFFER_LENGTH 512

%ifdef LOGGING
    %define STD_OUT DWORD -11
%endif

struc WSAData
    .wVersion        resw 1
    .wHighVersion    resw 1
    .iMaxSockets     resd 1
    .iMaxUdpDg       resd 1
    .lpVendorInfo    resq 1
    .szDescription   resb 257
    .szSystemStatus  resb 129
endstruc

struc PADDRINFOA
    .addrinfo       resq 1
endstruc

struc ADDRINFOA
    .ai_flags        resd 1
    .ai_family       resd 1
    .ai_socktype     resd 1
    .ai_protocol     resd 1
    .ai_addrlen      resq 1
    .ai_canonname    resq 1
    .ai_addr         resq 1
    .ai_next         resq 1
endstruc

%ifdef LOGGING
    struc LOCALTIME
        .wYear           resw 1
        .wMonth          resw 1
        .wDayOfWeek      resw 1
        .wDay            resw 1
        .wHour           resw 1
        .wMinute         resw 1
        .wSecond         resw 1
        .wMilliseconds   resw 1
    endstruc
%endif
section .text
entry:
    sub rsp, WIN64_STACK_SHADOW_THINGY ; Windows syscall stack space

    %ifdef LOGGING
        ; Init logging
        mov rcx, STD_OUT
        call GetStdHandle

        ; If we get -1 it failed
        cmp rax, -1
        je exit

        ; move our handle into a global
        mov [std_out_handle], rax

        ; Make our text green
        mov rcx, [std_out_handle]
        mov rdx, DWORD 0x0002
        call SetConsoleTextAttribute
        cmp rax, 0x00
        je exit
        
        call timestamp
        mov rdx, logging_init_msg
        mov r8, logging_init_msg_size
        call log
    %endif

    ; WSAStartup
    mov cx, VERSION_2_2
    mov rdx, wsadata
    call WSAStartup

    ; If we DONT get 0 it failed
    cmp rax, 0x00
    jne exit

    %ifdef LOGGING
        call timestamp
        mov rdx, wsa_start_msg
        mov r8, wsa_start_msg_size
        call log
    %endif

    ; getaddrinfo (For ai_addrlen)
    mov [addr_hint + ADDRINFOA.ai_family],  AF_UNSPEC
    mov [addr_hint + ADDRINFOA.ai_socktype], SOCK_STREAM
    mov [addr_hint + ADDRINFOA.ai_protocol], IPPROTO_TCP

    mov rcx, bind_addr
    mov rdx, bind_port
    mov r8, addr_hint
    mov r9, p_addr_info
    call getaddrinfo

    ; If we get 0 it failed
    cmp rax, 0x00
    jne exit

    %ifdef LOGGING
        call timestamp
        mov rdx, get_addr_info_msg
        mov r8, get_addr_info_msg_size
        call log
    %endif

    ; socket
    mov rcx, [addr_hint + ADDRINFOA.ai_family]
    mov rdx, [addr_hint + ADDRINFOA.ai_socktype]
    mov r8, [addr_hint + ADDRINFOA.ai_protocol]
    call socket ; rax will be socket handle
    mov [socket_descriptor], rax

    ; If we get -1 it failed
    cmp rax, -1
    je exit

    %ifdef LOGGING
        call timestamp
        mov rdx, create_socket_msg
        mov r8, create_socket_msg_size
        call log
    %endif

    ; bind
    mov r15, [p_addr_info]  ; Get the pointer to the addr_info struct returned
                            ; by out call to `getaddrinfo`
    mov rcx, [socket_descriptor]
    mov rdx, [r15 + ADDRINFOA.ai_addr]
    mov r8,  [r15 + ADDRINFOA.ai_addrlen]
    call bind ; rax will be socket handle

    ; If we dont get 0 it failed
    cmp rax, 0
    jne exit

    %ifdef LOGGING
        call timestamp
        mov rdx, bind_msg
        mov r8, bind_msg_size
        call log
    %endif

    ; listen
    mov rcx, [socket_descriptor]
    mov rdx, SOMAXCONN
    call listen

    ; If we dont get 0 it failed
    cmp rax, 0
    jne exit

    %ifdef LOGGING
        call timestamp
        mov rdx, listen_msg
        mov r8, listen_msg_size
        call log
    %endif

    ; Loop over connections
    handle_connection:
        ; accept
        mov rcx, [socket_descriptor]
        mov rdx, 0x00
        mov r8,  0x00
        call accept
        mov [client_socket], rax
        ; Returns a client socket into rax or -1 for failure

        ; recv
        mov rcx, [client_socket]
        mov rdx, recv_buf
        mov r8, DWORD RECV_BUFFER_LENGTH
        mov r9, 0x00
        call recv

        %ifdef LOGGING
            push rax
            call timestamp
            pop rax

            mov rdx, recv_buf
            mov r8, rax
            call log

        %endif

        ; send (Echo server so re-using recv_buf)
        mov rcx, [client_socket]
        mov rdx, recv_buf
        mov r8,  rax
        mov r9, 0x00
        call send

        ; Close the client socket
        mov rcx, [client_socket]
        call closesocket
        
        jmp handle_connection

        ; Exit with last return exit code
        jmp exit

%ifdef LOGGING
    ; rdx: char *, r8: len
    log:
        mov rcx, [std_out_handle]
        mov r9, 0x00
        call WriteConsoleA

        ; If WriteConsoleA exit with code -101
        cmp rax, 0
        jne .continue

        mov rax, -101
        jmp exit
        
        .continue:
        ret

    timestamp:
        ; let arr: [u8; 32];
        sub rsp, 0x20

        ; Get the current datetime
        mov rcx, localtime
        call GetLocalTime

        ; Timestamp len counter
        xor r15, r15

        mov BYTE [rsp + r15], BYTE "["
        inc r15 

        ; Get Year
        xor rcx, rcx
        lea rdx, [rsp + r15]
        mov cx, [localtime + LOCALTIME.wYear]
        call int_to_str
        ; Increment timestamp len
        add r15, rax

        mov BYTE [rsp + r15], BYTE "-"
        inc r15 

        ; Get month
        xor rcx, rcx
        lea rdx, [rsp + r15] 
        mov cx, [localtime + LOCALTIME.wMonth]
        call int_to_str
        add r15, rax

        mov BYTE [rsp + r15], BYTE "-"
        inc r15 

        ; Get day
        xor rcx, rcx
        lea rdx, [rsp + r15] 
        mov cx, [localtime + LOCALTIME.wDay]
        call int_to_str
        add r15, rax

        mov BYTE [rsp + r15], BYTE " "
        inc r15 

        ; Get Hour
        xor rcx, rcx
        lea rdx, [rsp + r15] 
        mov cx, [localtime + LOCALTIME.wHour]
        call int_to_str
        add r15, rax

        mov BYTE [rsp + r15], BYTE ":"
        inc r15 

        ; Get Hour
        xor rcx, rcx
        lea rdx, [rsp + r15] 
        mov cx, [localtime + LOCALTIME.wMinute]
        call int_to_str
        add r15, rax

        mov BYTE [rsp + r15], BYTE ":"
        inc r15 

        ; Get Second
        xor rcx, rcx
        lea rdx, [rsp + r15] 
        mov cx, [localtime + LOCALTIME.wSecond]
        call int_to_str
        add r15, rax

        mov BYTE [rsp + r15], BYTE "."
        inc r15 

        ; Get Millis
        xor rcx, rcx
        lea rdx, [rsp + r15] 
        mov cx, [localtime + LOCALTIME.wMilliseconds]
        call int_to_str
        add r15, rax

        mov WORD [rsp + r15], WORD "] "
        add r15, 2 
        
        mov rdx, rsp ; Array pointer
        mov r8, r15 ; Len
        call log 

        add rsp, 0x20
        ret
    ; We get the result in the wrong order as we work out the lowest
    ; number first, for example if we had 2964 our algorithm will
    ; calculate 4,6,9,2. So we reverse after calculation
    ; Fn int_to_str ( 
    ;   in rcx: Number to parse into str[],
    ;   out rdx: &[u8;20]
    ; ) -> rax: len 
    int_to_str:
        ; Move pointer to out memory into rdi
        mov rdi, rdx
        ; Move the input to rax
        mov rax, rcx
        ; Our counter for how many decimal places
        xor rcx, rcx
        ; Divide by 10
        mov rbx, 10
        .while:
            ; Zero our intial decimal part 
            xor rdx, rdx
            ; rax.rdx / rbx = rax remainder rdx
            div rbx
            ; Convert to ASCII
            add rdx, 48
            ; Store in our array as dl as its a char
            mov [rdi+rcx], dl
            ; Increment our counter
            inc rcx
            ; Check if the integer part of the result is zero
            cmp rax, 0x0
            ; Do until the integer part of the result is zero
            jne .while

        ; Save array length
        mov rsi, rcx

        ; Index Counter
        xor rbx, rbx
        ; Reverse array
        .reverse_byte_array:
        ; If array too small dont do it!
        mov dh, cl
        mov dl, bl
        sub dh, dl
        cmp dh, 0x01

        jle .reverse_byte_array_end
        ; Decrement array len count
        dec rcx
        mov al, [rdi + rbx]
        mov ah, [rdi + rcx]

        mov [rdi + rbx], ah
        mov [rdi + rcx], al
        ; Increment array index pointer
        inc rbx
        jmp .reverse_byte_array
        .reverse_byte_array_end:

        ; Return len
        mov rax, rsi

        ret
%endif

exit:
    mov rcx, rax
    call ExitProcess

section .data   
    ; For intialising the windows socket stuff
    wsadata: 
        ISTRUC WSAData
        IEND
    ; Information about the kind of socket I want
    addr_hint: 
        ISTRUC ADDRINFOA
        IEND
    ; Pointer to the struct that `getaddrinfo` fills in based on my addr_hint
    p_addr_info:
        ISTRUC PADDRINFOA
        IEND
    ; Storage for our socket described from `socket`, default -1 is failed state
    socket_descriptor: dq -1
    ; Storage for the socket of our current client connection, default -1 is failed state
    client_socket: dq -1
    ; Buffer to store incomming packet payloads
    recv_buf: times RECV_BUFFER_LENGTH db 0
    ; Store the logging handle
    %ifdef LOGGING
        std_out_handle: dq -1
        localtime:
            ISTRUC LOCALTIME
            IEND
    %endif

section .rodata
    ; Bind on all addresses
    bind_addr: db "0.0.0.0", 0
    ; Bind on port
    bind_port: db "6969", 0
    ; Store our log out messages
    %ifdef LOGGING
        logging_init_msg: db "Initialisation: Logging Enabled", 0x0A, 0x0D
        logging_init_msg_size: equ $ - logging_init_msg
        wsa_start_msg: db "Initialisation: WSAStartup Sucess", 0x0A, 0x0D
        wsa_start_msg_size: equ $ - wsa_start_msg
        get_addr_info_msg: db "Initialisation: getaddrinfo Sucess", 0x0A, 0x0D
        get_addr_info_msg_size: equ $ - get_addr_info_msg
        create_socket_msg: db "Initialisation: socket Sucess", 0x0A, 0x0D
        create_socket_msg_size: equ $ - create_socket_msg
        bind_msg: db "Initialisation: bind Sucess", 0x0A, 0x0D
        bind_msg_size: equ $ - bind_msg
        listen_msg: db "Initialisation: listen Sucess", 0x0A, 0x0D
        listen_msg_size: equ $ - listen_msg
    %endif