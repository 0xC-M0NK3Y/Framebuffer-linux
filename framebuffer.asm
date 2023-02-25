bits 64

SECTION .rodata
    fbname: db "/dev/fb0", 0
    rect_size: dd 50
    rect_color: dd 0xFF00FF00
    background_color: dd 0xFF303030
    ;sleep_time: dq 500000000

section .bss
    fd: resd 1
    infos: resb 160
    buflen: resd 1
    bufptr: resq 1
    width: resd 1
    heigth: resd 1
    width_len: resd 1 
    pos_x: resd 1
    pos_y: resd 1

SECTION .text

global main, _start

main:
_start:
    push rbp
    mov rbp, rsp
    sub rsp, 0x100                      ; allocate stack
    and rsp, 0xFFFFFFFFFFFFFFF0         ; align the stack

    ; STACK
    ;
    ; 16 [-0x10] NOTHING
    ;  1 [-0x11] char c
    ; 60 [-0x4D] struct termios
    ; 60 [-0x89] struct termios
    ;  4 [-0x8D] uint32_t height + rect_size
    ;  4 [-0x91] uint32_t width  + rect_size

    ; REGISTERS
    ;
    ; r14d -> pos_x 
    ; r13d -> pos_y
    ; r15b -> c
    ; r12  -> bufptr
    ;

    ; struct timespec for the nanosleep
    ;mov r8, [sleep_time]
    ;mov r9, 0
    ;mov [rbp-0x8], r8
    ;mov [rbp-0x10], r9

    mov rax, 0x10                       ; ioctl(
    xor rdi, rdi                        ; 0
    mov rsi, 0x5401                     ; TCGETS
    mov rdx, rbp                        ; &struct termios); // in the stack at -0x4D
    sub rdx, 0x4D
    syscall
    cmp rax, 0
    jl fail_end

    ; keep track of terminal state to reset it good at the end
    ; because we need to change proprity of terminal for the read
    ; (edit: seems like it resets alone)
    mov rdi, rbp
    sub rdi, 0x89
    mov rsi, rbp
    sub rsi, 0x4D
    mov rdx, 0x3C
    call _memcpy                        ; memcpy(&struct termios, &struct termios, 60);

    ; set the copied struct termios to "raw mode" (non blocking read)
    ; its working, escace and signals are not interpreted and it timeouts
    ; but just the cursor is still there '-'
    mov DWORD [rbp-0x51], DWORD 528
    mov DWORD [rbp-0x55], DWORD 0
    mov DWORD [rbp-0x5D], DWORD 0x7fb4
    mov DWORD [rbp-0x61], DWORD 0
    mov BYTE  [rbp-0x64], BYTE 1 ; VTIME
    mov BYTE  [rbp-0x65], BYTE 0 ; VMIN
    mov DWORD [rbp-0x83], DWORD 0x7FFD
    mov DWORD [rbp-0x89], DWORD 100

    mov rax, 0x10                     ; ioctl(
    xor rdi, rdi                      ; 0,
    mov rsi, 0x5404                   ; TCSETSF,
    mov rdx, rbp                      ; &struct termios); // in the stack at -0x89
    sub rbp, 0x89
    syscall
    add rbp, 0x89
    cmp rax, 0
    jl fail_end

    ; open the framebuffer "/dev/fb0"
    mov rax, 0x2                        ; open(
    mov rdi, fbname                     ; "/dev/fb0",
    mov rsi, 0x2                        ; O_RDRW);
    syscall
    cmp rax, 0
    jl fail_end                         ; if (fd < 0)
    mov [fd], eax

    ; get attribute of the screen
    xor rdi, rdi
    mov rax, 0x10                       ; ioctl(
    mov edi, [fd]                       ; fd,
    mov rsi, 0x4600                     ; FBIOGET_VSCREENINFO,
    mov rdx, infos                      ; &struct fb_var_screeninfo infos);
    syscall
    cmp rax, 0                          
    jl fail_end                         ; if (ret < 0)

    ; calcule the buffer len we need to mmap
    xor rdx, rdx
    xor rax, rax
    mov edx, DWORD [infos]              ; infos.xres
    mov eax, DWORD [infos+0x4]          ; infos.yres
    mov [width], edx
    mov [heigth], eax
    mul rdx                             ; infox.xres * infos.yres
    xor rdx, rdx
    mov edx, DWORD [infos+0x18]         ; infos.bits_per_pixel
    mul rdx                             ; (infox.xres * infos.yres) * infos.bits_per_pixel
    mov r8, 0x8
    div r8                              ; ((infox.xres * infos.yres) * infos.bits_per_pixel) / 8
    mov [buflen], rax

    ; map the framebuffer into the RAM
    mov rax, 0x9                        ; mmap(
    xor rdi, rdi                        ; NULL,
    mov rsi, [buflen]                   ; buflen,
    mov rdx, 0x3                        ; PROT_READ|PROT_WRITE,
    mov r10, 0x0001                     ; MAP_SHARED,
    mov r8, [fd]                        ; fd,
    xor r9, r9                          ; 0);
    syscall
    cmp rax, 0xffffffffffffffff
    je fail_end                         ; if (ret == (void *)-1)

    mov [bufptr], rax                   ; bufptr = ret

    xor rax, rax
    mov eax, DWORD [buflen]
    mov r8, 0x4
    div r8
    mov [buflen], DWORD eax             ; buflen /= 4 (to have len of uint32_t *)

    ; i like xoring just to be sure not necessary
    xor r15, r15
    xor r14, r14
    xor r13, r13
    xor r10, r10
    
    mov r10d, DWORD [width]
    imul r10d, 4
    mov [width_len], DWORD r10d          ; width_len = 1920*4

    ; make the rectangle spawn in the middle of the screen
    mov eax, [width]
    mov ecx, 0x2
    div ecx
    mov r14d, eax
    sub r14d, DWORD [rect_size]
    mov eax, [heigth]
    mov ecx, 0x2
    div ecx
    mov r13d, eax
    sub r13d, DWORD [rect_size]

    mov r10d, DWORD [heigth]
    sub r10d, DWORD [rect_size]
    mov DWORD [rbp-0x8D], r10d

    mov r10d, DWORD [width]
    sub r10d, DWORD [rect_size]
    mov DWORD [rbp-0x91], r10d

    ; to optimize use a most registers as possible
    mov r12, [bufptr]
    mov BYTE [rbp-0x11], BYTE 0

    mov rdi, r12
    mov esi, [buflen]
    mov edx, DWORD [background_color]
    call fill_screen                    ; fill_screen(bufptr, buflen, color);

while1:
    ; while (1)
    mov rdi, r12
    mov esi, DWORD [rect_size]
    mov edx, r14d
    mov ecx, r13d
    call draw_rectangle                 ; draw_rectangle(bufptr, buflen, size, pos_x, pos_y);

    ;mov rax, 0x23               ; nano_sleep(
    ;mov rdi, rbp                ; &struct timespec, // in the stack of the main
    ;sub rdi, 0x10               ;
    ;xor rsi, rsi                ; NULL);
    ;syscall

    ; non-blocking return after certain amout of time
    ; so read actually perfoms a "sleep"

    xor rax, rax                ; read(
    xor rdi, rdi                ; 0,
    mov rsi, rbp                ; &c, // in the stack
    sub rsi, 0x11
    mov rdx, 0x1                ; 1);
    syscall
    cmp rax, 0
    jl fail_end
    je while1

    xor r15, r15
    mov r15b, BYTE [rbp-0x11]
    cmp r15b, 0x0
    je while1
    cmp r15b, 0x7A ; 'z'
    je move_up
    cmp r15b, 0x73; 's'
    je move_down
    cmp r15b, 0x64 ; 'd'
    je move_right
    cmp r15b, 0x71 ; 'q'
    je move_left
    cmp r15b, 0x65 ; 'e'
    je end
    jmp while1

end:
    mov rax, 0xB
    mov rdi, [bufptr]
    mov rsi, [buflen]
    syscall             ; munmap

    mov rax, 0x3
    mov rdi, [fd]
    syscall             ; close

    mov rax, 0x10                     ; ioctl(
    xor rdi, rdi                      ; 0,
    mov rsi, 0x5404                   ; TCSETSF,
    mov rdx, rbp                      ; &struct termios); // in the stack at -0x4D (original)
    sub rdx, 0x4D
    syscall

    mov rbp, rsp
    pop rbp

    mov rax, 0x3C                       ; exit
    mov rdi, 0
    syscall

fail_end:
    mov rax, 0x10                     ; ioctl(
    xor rdi, rdi                      ; 0,
    mov rsi, 0x5404                   ; TCSETSF,
    mov rdx, rbp                      ; &struct termios); // in the stack at -0x4D (original)
    sub rdx, 0x4D
    syscall

    mov rbp, rsp
    pop rbp

    mov rax, 0x3C
    mov rdi, 1
    syscall

move_up:
    cmp r13d, 5
    jbe while1
    dec r13d
    dec r13d
    dec r13d
    dec r13d
    jmp while1
move_down:
    cmp r13d, DWORD [rbp-0x8D]
    jae while1
    inc r13d
    inc r13d
    inc r13d
    inc r13d
    jmp while1
move_right:
    cmp r14d, DWORD [rbp-0x91]
    jae while1
    inc r14d
    inc r14d
    inc r14d
    inc r14d
    jmp while1
move_left:
    cmp r14d, 5
    jbe while1
    dec r14d
    dec r14d
    dec r14d
    dec r14d
    jmp while1


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void fill_screen(uint32_t *ptr, uint32_t len, uint32_t color);
fill_screen:
    push r8
    xor r8, r8 
for_1:
    mov [rdi+r8*4], edx
    inc r8
    cmp r8d, esi
    jne for_1

    pop r8
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void draw_rectancle(uint32_t *ptr, uint32_t size, int pos_x, int pos_y)
draw_rectangle:
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    push rbx

    mov r11d, edx            ; r11 = x
    mov r12d, ecx            ; r12 = y
    mov r15d, edx

    mov r8d, edx
    add r8d, esi             ; r8 = x + size
    mov r9d, ecx
    add r9d, esi             ; r9 = y + size

    mov eax, DWORD [rect_color] ; rax = rect_color
    mov r10d, DWORD [width_len] ; r10 = 1920*4

    xor rbx, rbx
    mov ebx, 0x4

    xor r14, r14
    xor r13, r13
    mov r13d, r11d
    imul r13d, ebx          ; r13 = x*4
    mov r14d, r12d
    imul r14d, r10d         ; r14 = y*width_len
    add r14d, r13d          ; r14 = (x*4)+(y*width_len)

    imul esi, ebx

for_3:
    mov r11d, r15d
for_2:
    mov [rdi+r14], DWORD eax

    add r14d, 0x4
    inc r11d
    cmp r11d, r8d
    jl for_2

    inc r12d
    add r14d, r10d
    sub r14d, esi
    cmp r12d, r9d
    jl for_3

    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    mov rax, 0x1A
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void memcpy(void *dest, void *src, uint32_t size);
_memcpy:
    push r8
    push r9
    xor r9, r8
    xor r8, r8
for_4:
    mov r9b, BYTE [rsi+r8]
    mov BYTE [rdi+r8], r9b
    inc r8
    cmp r8, rdx
    jl for_4
    pop r9
    pop r8
    ret


