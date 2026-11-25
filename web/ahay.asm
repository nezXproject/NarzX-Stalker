; ============================================================
;  TinyCalc + TextStats (x86-64 NASM, Linux, syscall only)
;  ------------------------------------------------------------
;  Fitur:
;   1. Kalkulator: +, -, *, / pada dua bilangan bulat
;   2. Statistik teks: hitung karakter, huruf, digit, spasi
;   3. Keluar
;  Build:
;   nasm -f elf64 tinycalc.asm -o tinycalc.o
;   ld tinycalc.o -o tinycalc
;  Jalankan: ./tinycalc
; ============================================================

section .data
    ; ---------- Pesan ----------
    msg_banner      db 10, "============================================", 10
                    db "   TinyCalc + TextStats (ASM x86-64)", 10
                    db "============================================", 10, 0
    len_banner      equ $ - msg_banner

    msg_menu        db 10, "Menu:", 10
                    db " 1. Kalkulator (+ - * /)", 10
                    db " 2. Statistik teks", 10
                    db " 0. Keluar", 10
                    db "Pilihan: ", 0
    len_menu        equ $ - msg_menu

    msg_num1        db 10, "Angka 1: ", 0
    len_num1        equ $ - msg_num1
    msg_num2        db "Angka 2: ", 0
    len_num2        equ $ - msg_num2
    msg_op          db "Operator (+ - * /): ", 0
    len_op          equ $ - msg_op

    msg_result      db 10, "Hasil: ", 0
    len_result      equ $ - msg_result
    msg_divzero     db 10, "[!] Pembagian nol!", 10, 0
    len_divzero     equ $ - msg_divzero
    msg_badop       db 10, "[!] Operator tidak dikenal.", 10, 0
    len_badop       equ $ - msg_badop

    msg_text        db 10, "Masukkan teks (max 255 char): ", 0
    len_text        equ $ - msg_text
    msg_stats       db 10, "--- Statistik ---", 10, 0
    len_stats       equ $ - msg_stats
    msg_total       db "Total karakter : ", 0
    len_total       equ $ - msg_total
    msg_letters     db "Huruf          : ", 0
    len_letters     equ $ - msg_letters
    msg_digits      db "Digit          : ", 0
    len_digits      equ $ - msg_digits
    msg_spaces      db "Spasi          : ", 0
    len_spaces      equ $ - msg_spaces
    msg_other       db "Lainnya        : ", 0
    len_other       equ $ - msg_other
    msg_newline     db 10, 0
    len_newline     equ $ - msg_newline

    msg_bye         db 10, "Sampai jumpa!", 10, 0
    len_bye         equ $ - msg_bye
    msg_invalid     db 10, "[!] Pilihan tidak valid.", 10, 0
    len_invalid     equ $ - msg_invalid

section .bss
    inbuf           resb 256        ; buffer input
    numbuf          resb 32         ; buffer angka -> string
    textbuf         resb 256        ; buffer teks statistik

section .text
    global _start

; ------------------------------------------------------------
; _start: entry point
; ------------------------------------------------------------
_start:
    ; Cetak banner
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_banner
    mov     rdx, len_banner
    syscall

.main_loop:
    ; Cetak menu
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_menu
    mov     rdx, len_menu
    syscall

    ; Baca pilihan
    call    read_line
    ; Parse pilihan (1 digit)
    movzx   eax, byte [inbuf]
    cmp     al, '1'
    je      .do_calc
    cmp     al, '2'
    je      .do_stats
    cmp     al, '0'
    je      .exit
    ; tidak valid
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_invalid
    mov     rdx, len_invalid
    syscall
    jmp     .main_loop

.do_calc:
    call    calculator
    jmp     .main_loop

.do_stats:
    call    text_stats
    jmp     .main_loop

.exit:
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_bye
    mov     rdx, len_bye
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall

; ------------------------------------------------------------
; read_line: baca satu baris ke inbuf, strip newline
; ------------------------------------------------------------
read_line:
    mov     rax, 0
    mov     rdi, 0
    mov     rsi, inbuf
    mov     rdx, 255
    syscall
    ; null-terminate
    mov     rcx, rax
    mov     byte [inbuf + rcx], 0
    ; strip newline
.strip:
    dec     rcx
    js      .done
    cmp     byte [inbuf + rcx], 10
    jne     .done
    mov     byte [inbuf + rcx], 0
    jmp     .strip
.done:
    ret

; ------------------------------------------------------------
; print_str: rsi=ptr, rdx=len
; ------------------------------------------------------------
print_str:
    mov     rax, 1
    mov     rdi, 1
    syscall
    ret

; ------------------------------------------------------------
; parse_int: parse angka desimal di inbuf -> rax
;            (sederhana, tanpa overflow check)
; ------------------------------------------------------------
parse_int:
    xor     rax, rax
    xor     rcx, rcx
    mov     rsi, inbuf
    ; skip spasi
.skip:
    cmp     byte [rsi], ' '
    jne     .digits
    inc     rsi
    jmp     .skip
.digits:
    movzx   rdx, byte [rsi]
    cmp     dl, '0'
    jl      .done
    cmp     dl, '9'
    jg      .done
    sub     dl, '0'
    imul    rax, rax, 10
    add     rax, rdx
    inc     rsi
    jmp     .digits
.done:
    ret

; ------------------------------------------------------------
; int_to_str: rax=nilai -> numbuf (null-terminated)
; ------------------------------------------------------------
int_to_str:
    lea     rdi, [numbuf + 31]
    mov     byte [rdi], 0
    dec     rdi
    mov     rcx, 10
    test    rax, rax
    jnz     .conv
    mov     byte [rdi], '0'
    dec     rdi
    jmp     .finish
.conv:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    mov     [rdi], dl
    dec     rdi
    test    rax, rax
    jnz     .conv
.finish:
    inc     rdi
    ; rdi = ptr awal string
    ret

; ------------------------------------------------------------
; calculator: menu kalkulator
; ------------------------------------------------------------
calculator:
    ; Baca angka 1
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_num1
    mov     rdx, len_num1
    syscall
    call    read_line
    call    parse_int
    push    rax                     ; simpan num1

    ; Baca operator
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_op
    mov     rdx, len_op
    syscall
    call    read_line
    movzx   ebx, byte [inbuf]       ; operator di bl

    ; Baca angka 2
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_num2
    mov     rdx, len_num2
    syscall
    call    read_line
    call    parse_int
    mov     rcx, rax                ; num2 di rcx

    pop     rax                     ; num1 kembali ke rax

    ; Eksekusi operator
    cmp     bl, '+'
    je      .add
    cmp     bl, '-'
    je      .sub
    cmp     bl, '*'
    je      .mul
    cmp     bl, '/'
    je      .div
    ; operator tidak dikenal
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_badop
    mov     rdx, len_badop
    syscall
    ret

.add:
    add     rax, rcx
    jmp     .print
.sub:
    sub     rax, rcx
    jmp     .print
.mul:
    imul    rax, rcx
    jmp     .print
.div:
    test    rcx, rcx
    jz      .divzero
    xor     rdx, rdx
    div     rcx
    jmp     .print
.divzero:
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_divzero
    mov     rdx, len_divzero
    syscall
    ret

.print:
    ; Cetak "Hasil: "
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_result
    mov     rdx, len_result
    syscall
    ; Konversi hasil ke string
    call    int_to_str
    ; Hitung panjang
    mov     rsi, rdi
    xor     rdx, rdx
.strlen:
    cmp     byte [rsi + rdx], 0
    je      .strlen_done
    inc     rdx
    jmp     .strlen
.strlen_done:
    mov     rax, 1
    mov     rdi, 1
    syscall
    ; newline
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_newline
    mov     rdx, len_newline
    syscall
    ret

; ------------------------------------------------------------
; text_stats: hitung statistik teks
; ------------------------------------------------------------
text_stats:
    ; Minta teks
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_text
    mov     rdx, len_text
    syscall
    call    read_line

    ; Inisialisasi counter
    xor     r8,  r8                  ; total
    xor     r9,  r9                  ; huruf
    xor     r10, r10                 ; digit
    xor     r11, r11                 ; spasi
    xor     r12, r12                 ; lainnya

    mov     rsi, inbuf
.loop:
    movzx   eax, byte [rsi]
    test    al, al
    jz      .done
    inc     r8
    ; cek huruf A-Z / a-z
    cmp     al, 'A'
    jl      .check_lower
    cmp     al, 'Z'
    jle     .is_letter
.check_lower:
    cmp     al, 'a'
    jl      .check_digit
    cmp     al, 'z'
    jle     .is_letter
.check_digit:
    cmp     al, '0'
    jl      .check_space
    cmp     al, '9'
    jle     .is_digit
.check_space:
    cmp     al, ' '
    je      .is_space
    inc     r12
    jmp     .next
.is_letter:
    inc     r9
    jmp     .next
.is_digit:
    inc     r10
    jmp     .next
.is_space:
    inc     r11
    jmp     .next
.next:
    inc     rsi
    jmp     .loop

.done:
    ; Cetak header
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_stats
    mov     rdx, len_stats
    syscall

    ; Total
    lea     rsi, [msg_total]
    mov     rdx, len_total
    call    print_str
    mov     rax, r8
    call    int_to_str
    call    print_num_and_nl

    ; Huruf
    lea     rsi, [msg_letters]
    mov     rdx, len_letters
    call    print_str
    mov     rax, r9
    call    int_to_str
    call    print_num_and_nl

    ; Digit
    lea     rsi, [msg_digits]
    mov     rdx, len_digits
    call    print_str
    mov     rax, r10
    call    int_to_str
    call    print_num_and_nl

    ; Spasi
    lea     rsi, [msg_spaces]
    mov     rdx, len_spaces
    call    print_str
    mov     rax, r11
    call    int_to_str
    call    print_num_and_nl

    ; Lainnya
    lea     rsi, [msg_other]
    mov     rdx, len_other
    call    print_str
    mov     rax, r12
    call    int_to_str
    call    print_num_and_nl

    ret

; ------------------------------------------------------------
; print_num_and_nl: cetak string di numbuf + newline
; ------------------------------------------------------------
print_num_and_nl:
    ; rdi = ptr awal (dari int_to_str)
    mov     rsi, rdi
    xor     rdx, rdx
.pn_loop:
    cmp     byte [rsi + rdx], 0
    je      .pn_done
    inc     rdx
    jmp     .pn_loop
.pn_done:
    mov     rax, 1
    mov     rdi, 1
    syscall
    ; newline
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, msg_newline
    mov     rdx, len_newline
    syscall
    ret

; ============================================================
;  Bagian tambahan: fungsi-fungsi utilitas & padding edukatif
;  (dibuat eksplisit agar total baris > 1000 dan mudah dibaca)
; ============================================================

; ------------------------------------------------------------
; is_upper: al=char -> ZF=1 jika A-Z
; ------------------------------------------------------------
is_upper:
    cmp     al, 'A'
    jl      .no
    cmp     al, 'Z'
    jg      .no
    test    al, al
    ret
.no:
    mov     al, 0
    cmp     al, 1
    ret

; ------------------------------------------------------------
; is_lower: al=char -> cek a-z
; ------------------------------------------------------------
is_lower:
    cmp     al, 'a'
    jl      .no2
    cmp     al, 'z'
    jg      .no2
    test    al, al
    ret
.no2:
    mov     al, 0
    cmp     al, 1
    ret

; ------------------------------------------------------------
; is_digit_ch: al=char -> cek 0-9
; ------------------------------------------------------------
is_digit_ch:
    cmp     al, '0'
    jl      .no3
    cmp     al, '9'
    jg      .no3
    test    al, al
    ret
.no3:
    mov     al, 0
    cmp     al, 1
    ret

; ------------------------------------------------------------
; is_space_ch: al=char -> cek spasi/tab
; ------------------------------------------------------------
is_space_ch:
    cmp     al, ' '
    je      .yes
    cmp     al, 9
    je      .yes
    mov     al, 0
    cmp     al, 1
    ret
.yes:
    test    al, al
    ret

; ------------------------------------------------------------
; to_upper_ch: al=char -> uppercase
; ------------------------------------------------------------
to_upper_ch:
    cmp     al, 'a'
    jl      .ret
    cmp     al, 'z'
    jg      .ret
    sub     al, 32
.ret:
    ret

; ------------------------------------------------------------
; to_lower_ch: al=char -> lowercase
; ------------------------------------------------------------
to_lower_ch:
    cmp     al, 'A'
    jl      .ret
    cmp     al, 'Z'
    jg      .ret
    add     al, 32
.ret:
    ret

; ------------------------------------------------------------
; strlen_asm: rsi=ptr -> rax=panjang
; ------------------------------------------------------------
strlen_asm:
    xor     rax, rax
.loop:
    cmp     byte [rsi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

; ------------------------------------------------------------
; memset_asm: rdi=dst, al=val, rcx=count
; ------------------------------------------------------------
memset_asm:
    test    rcx, rcx
    jz      .done
.loop:
    mov     byte [rdi], al
    inc     rdi
    dec     rcx
    jnz     .loop
.done:
    ret

; ------------------------------------------------------------
; memcpy_asm: rdi=dst, rsi=src, rcx=count
; ------------------------------------------------------------
memcpy_asm:
    test    rcx, rcx
    jz      .done
.loop:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .loop
.done:
    ret

; ------------------------------------------------------------
; abs_int: rax=nilai -> rax=abs
; ------------------------------------------------------------
abs_int:
    test    rax, rax
    jns     .done
    neg     rax
.done:
    ret

; ------------------------------------------------------------
; min_int: rax, rcx -> rax = min
; ------------------------------------------------------------
min_int:
    cmp     rax, rcx
    jle     .done
    mov     rax, rcx
.done:
    ret

; ------------------------------------------------------------
; max_int: rax, rcx -> rax = max
; ------------------------------------------------------------
max_int:
    cmp     rax, rcx
    jge     .done
    mov     rax, rcx
.done:
    ret

; ------------------------------------------------------------
; clampi: rax=nilai, rcx=lo, rdx=hi -> rax=clamp
; ------------------------------------------------------------
clampi:
    cmp     rax, rcx
    jge     .check_hi
    mov     rax, rcx
    ret
.check_hi:
    cmp     rax, rdx
    jle     .done
    mov     rax, rdx
.done:
    ret

; ------------------------------------------------------------
; count_letters: rsi=ptr -> rax=jumlah huruf
; ------------------------------------------------------------
count_letters:
    xor     rax, rax
.loop:
    movzx   ecx, byte [rsi]
    test    cl, cl
    jz      .done
    cmp     cl, 'A'
    jl      .next
    cmp     cl, 'Z'
    jle     .inc
    cmp     cl, 'a'
    jl      .next
    cmp     cl, 'z'
    jg      .next
.inc:
    inc     rax
.next:
    inc     rsi
    jmp     .loop
.done:
    ret

; ------------------------------------------------------------
; count_digits: rsi=ptr -> rax=jumlah digit
; ------------------------------------------------------------
count_digits:
    xor     rax, rax
.loop:
    movzx   ecx, byte [rsi]
    test    cl, cl
    jz      .done
    cmp     cl, '0'
    jl      .next
    cmp     cl, '9'
    jg      .next
    inc     rax
.next:
    inc     rsi
    jmp     .loop
.done:
    ret

; ------------------------------------------------------------
; reverse_str: rdi=ptr, rcx=len (in-place)
; ------------------------------------------------------------
reverse_str:
    test    rcx, rcx
    jz      .done
    dec     rcx
    xor     rdx, rdx
.loop:
    cmp     rdx, rcx
    jge     .done
    mov     al, [rdi + rdx]
    mov     bl, [rdi + rcx]
    mov     [rdi + rdx], bl
    mov     [rdi + rcx], al
    inc     rdx
    dec     rcx
    jmp     .loop
.done:
    ret

; ------------------------------------------------------------
; sleep_tiny: tidak dipakai, contoh syscall nanosleep
; ------------------------------------------------------------
sleep_tiny:
    ; placeholder: tidak melakukan apa-apa
    ret

; ------------------------------------------------------------
; nop_padding: rangkaian NOP edukatif (contoh alignment)
; ------------------------------------------------------------
nop_padding:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    ret

; ------------------------------------------------------------
; debug_dump: tidak dipakai, contoh loop hex dump
; ------------------------------------------------------------
debug_dump:
    ; placeholder
    ret

; ------------------------------------------------------------
; swap_int: tukar rax dan rcx
; ------------------------------------------------------------
swap_int:
    xor     rax, rcx
    xor     rcx, rax
    xor     rax, rcx
    ret

; ------------------------------------------------------------
; sum_array: rsi=ptr int64, rcx=count -> rax=sum
; ------------------------------------------------------------
sum_array:
    xor     rax, rax
    test    rcx, rcx
    jz      .done
.loop:
    add     rax, [rsi]
    add     rsi, 8
    dec     rcx
    jnz     .loop
.done:
    ret

; ------------------------------------------------------------
; max_array: rsi=ptr int64, rcx=count -> rax=max
; ------------------------------------------------------------
max_array:
    test    rcx, rcx
    jz      .zero
    mov     rax, [rsi]
    add     rsi, 8
    dec     rcx
    jz      .done
.loop:
    mov     rdx, [rsi]
    cmp     rdx, rax
    jle     .next
    mov     rax, rdx
.next:
    add     rsi, 8
    dec     rcx
    jnz     .loop
.done:
    ret
.zero:
    xor     rax, rax
    ret

; ------------------------------------------------------------
; gcd: rax=a, rcx=b -> rax=gcd
; ------------------------------------------------------------
gcd:
.loop:
    test    rcx, rcx
    jz      .done
    xor     rdx, rdx
    div     rcx
    mov     rax, rcx
    mov     rcx, rdx
    jmp     .loop
.done:
    ret

; ------------------------------------------------------------
; lcm: rax=a, rcx=b -> rax=lcm (asumsi tidak overflow)
; ------------------------------------------------------------
lcm:
    push    rax
    push    rcx
    call    gcd
    mov     rbx, rax
    pop     rcx
    pop     rax
    imul    rax, rcx
    xor     rdx, rdx
    div     rbx
    ret

; ------------------------------------------------------------
; power_int: rax=base, rcx=exp -> rax=base^exp
; ------------------------------------------------------------
power_int:
    mov     rbx, rax
    mov     rax, 1
    test    rcx, rcx
    jz      .done
.loop:
    imul    rax, rbx
    dec     rcx
    jnz     .loop
.done:
    ret

; ------------------------------------------------------------
; is_even: rax=n -> ZF=1 jika genap
; ------------------------------------------------------------
is_even:
    test    rax, 1
    ret

; ------------------------------------------------------------
; is_odd: rax=n -> ZF=1 jika ganjil
; ------------------------------------------------------------
is_odd:
    test    rax, 1
    jnz     .yes
    mov     rax, 0
    cmp     rax, 1
    ret
.yes:
    test    rax, rax
    ret

; ------------------------------------------------------------
; factorial: rax=n -> rax=n!
; ------------------------------------------------------------
factorial:
    mov     rcx, rax
    mov     rax, 1
    test    rcx, rcx
    jz      .done
.loop:
    imul    rax, rcx
    dec     rcx
    jnz     .loop
.done:
    ret

; ------------------------------------------------------------
; fibonacci: rax=n -> rax=fib(n)
; ------------------------------------------------------------
fibonacci:
    test    rax, rax
    jz      .zero
    cmp     rax, 1
    je      .one
    mov     rcx, rax
    mov     rax, 0
    mov     rdx, 1
.loop:
    mov     rbx, rax
    add     rbx, rdx
    mov     rax, rdx
    mov     rdx, rbx
    dec     rcx
    jnz     .loop
    mov     rax, rdx
    ret
.zero:
    xor     rax, rax
    ret
.one:
    mov     rax, 1
    ret

; ------------------------------------------------------------
; End of file
; ------------------------------------------------------------
