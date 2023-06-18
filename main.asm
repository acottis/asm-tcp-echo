[BITS 64]
DEFAULT REL
global entry

; How to call windows x64
; https://github.com/simon-whitehead/assembly-fun/blob/master/windows-x64/README.md
; https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention?view=msvc-170
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

%define WIN64_STACK_SHADOW_THINGY 0x28
%define VERSION_2_2 WORD 0x0202
%define AF_UNSPEC DWORD 0x00
%define SOCK_STREAM DWORD 0x01
%define IPPROTO_TCP DWORD 0x06
%define SOMAXCONN DWORD 0x7fffffff
%define RECV_BUFFER_LENGTH 512

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

section .text
entry:
    sub rsp, WIN64_STACK_SHADOW_THINGY ; Windows syscall stack space

    ; WSAStartup
    mov rdx, wsadata
    mov cx, VERSION_2_2
    call WSAStartup

    ; getaddrinfo (For ai_addrlen)
    mov [addr_hint + ADDRINFOA.ai_family],  AF_UNSPEC
    mov [addr_hint + ADDRINFOA.ai_socktype], SOCK_STREAM
    mov [addr_hint + ADDRINFOA.ai_protocol], IPPROTO_TCP

    mov rcx, bind_addr
    mov rdx, bind_port
    mov r8, addr_hint
    mov r9, p_addr_info
    call getaddrinfo

    ; socket
    mov rcx, [addr_hint + ADDRINFOA.ai_family]
    mov rdx, [addr_hint + ADDRINFOA.ai_socktype]
    mov r8, [addr_hint + ADDRINFOA.ai_protocol]
    call socket ; rax will be socket handle
    mov [socket_descriptor], rax

    ; bind
    mov r15, [p_addr_info]  ; Get the pointer to the addr_info struct returned
                            ; by out call to `getaddrinfo`
    mov rcx, [socket_descriptor]
    mov rdx, [r15 + ADDRINFOA.ai_addr]
    mov r8,  [r15 + ADDRINFOA.ai_addrlen]
    call bind ; rax will be socket handle

    ; listen
    mov rcx, [socket_descriptor]
    mov rdx, SOMAXCONN
    call listen

    ; LOOP START HERE
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

    ; send (Echo server so reusing recv_buf)
    mov rcx, [client_socket]
    mov rdx, recv_buf
    mov r8,  rax
    mov r9, 0x00
    call send

    ; Close the client socket
    mov rcx, [client_socket]
    call closesocket

    ; Exit with last return exit code
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

section .rodata
    ; Bind on all addresses
    bind_addr: db "0.0.0.0", 0
    ; Bind on port
    bind_port: db "6969", 0 