[bits 64]

default rel
global ieeefp                   ; must be declared for linker (ld)

; ------------------------------------------------------------------------
section .bss

fladdsubflag: resb 1
sign1: resb 1
sign2: resb 1
signdiff: resb 1
exp1:  resb 1
exp2:  resb 1
tmpb:  resb 3
mask:  resb 3
flacc: resb 4

; ------------------------------------------------------------------------
section .text

ieeefp:                         ; entry point for linker
; integer arguments 1-6 are passed in the registers RDI, RSI, RDX, RCX, R8, R9
; floating-point arguments are passed in XMM0..7
; RBX must be saved by this routine (as callee)
   push  rbx
   push  ieeefpret     ; set return point

   mov   ecx,edi       ; operation code
   movq  rax,xmm0      ; argument 1
   movq  rbx,xmm1      ; argument 2

; DEBUG
;    mov  eax,$40E00000
;    mov  ebx,$40A00000

   test  cl,cl
   jz    fladd
   cmp   cl,1
   jz    flsub
   cmp   cl,2
   jz    flmult
   cmp   cl,3
   jz    fldiv
   ret                 ; unknown operation - return first argument as result

; return point from all routines - restore RBX before returning to caller
ieeefpret:
   pop   rbx
   ret

flsub:
   mov   dl,1          ; 1 = subtract
   jmp   fladdsub
fladd:
   mov   dl,0          ; 0 = add

fladdsub:
   test  ebx,ebx       ; B was 0; return with A as result
   jnz   .a1
   ret
.a1:
   test  eax,eax
   jnz   .a3
   test  dl,dl
   jz    .a2
   btc   ebx,31         ; negate B for 0-B (flip bit 31 and ignore test->carry)
.a2:
   mov   eax,ebx
   ret                  ; return B or -B

.a3:
   mov   BYTE [fladdsubflag],dl
   call  flunpack
   mov   cl,[exp1]
   sub   cl,[exp2]      ; compare exponents
   jz    noshift
   jnc   noexpswap

; swap operands
   mov   BYTE [tmpb],cl ; save exponent difference in tmpb
   mov   cl,BYTE [exp2]
   mov   BYTE [exp1],cl ; use second exponent as first; original second not needed
   xchg  eax,ebx        ; swap fractions

; swap sign if:
; for addition - signs are different
; for subtraction - signs are the same
   mov   cl,BYTE [fladdsubflag]
   xor   cl,BYTE [signdiff]
   and   cl,1
   jz    nexp
   xor   cl,BYTE [sign1]   ; with A=1, i.e. invert bit 0
   mov   BYTE [sign1],cl   ; and store as result sign
nexp:
   mov   cl,BYTE [tmpb]
   neg   cl             ; negate exponent difference

noexpswap:
   cmp   cl,24

; exponent difference too large; use first operand as result
   jnc   repack         ; finish with fraction from flaccA

; shift fraction2 right until exponents match
   shr   ebx,cl

noshift:
   mov   cl,BYTE [fladdsubflag]  ; get add/sub flag (0/1)
   xor   cl,BYTE [signdiff]
   mov   BYTE [fladdsubflag],cl  ; change operation if signs are different
;   and   cl,1
   jnz   fldosub

; add two fractions
   add   eax,ebx
   bt    eax,24
   jnc   checknorm      ; no overflow from addition
   jmp   checkbit24

; subtract two fractions
fldosub:
   sub   eax,ebx
   test  eax,0xFF000000
   jz    checknorm      ; no overflow from subtraction

checkbit24:
   test  BYTE [fladdsubflag],1
   jnz   fracneg

; overflow after addition requires shifting fraction right and incrementing exponent
   shr   eax,1          ; rounding maybe?
   inc   BYTE [exp1]
   jmp   repack

; a negative fraction after subtraction requires negating fraction and changing sign
fracneg:
   neg   eax              ; negate fraction
   neg   BYTE [sign1]     ; negate sign
   jmp   checknorm2

checknorm:
; check if fraction is zero first (from subtraction)
   test  eax,$00FFFFFF
   jnz   checknorm2
   mov   eax,0
   ret                    ; finish, with everything = 0

checknorm2:
   test  BYTE [fladdsubflag],1
   jz    repack

; normalisation of fraction - used by subtraction, multiplication & division
normalise:
   and   eax,$00FFFFFF     ; clear bits 31-24 first
norm1:
   bt    eax,23            ; test bit 23
   jc    repack
   shl   eax,1
   dec   BYTE [exp1]
   jnz   norm1

; fraction underflow - leave result as zero
; may occur from multiplication or division
   mov   eax,0
   ret

; repack components into IEEE float - used by all arithmetic operations
repack:
   and   eax,$007FFFFF     ; clear bits 31-23
   mov   cl,BYTE [exp1]
;   bswap ecx               ; move exponent to top 8 bits: 31-24
   shl   ecx,24
   shr   BYTE [sign1],1
   rcr   ecx,1
   and   ecx,0xFF800000
   or    eax,ecx
   clc
finished:
   ret                     ; finished: result is in flaccA (and carry is clear for division flag)



; ------------------------------------------------------------------------
; Extract signs and exponents, and make real 24-bit fractions.
; Called by all arithmetic routines.
;
flunpack:
   mov   BYTE [sign1],0
   mov   BYTE [sign2],0      ; clear sign bytes first so only bit 0 is used

   mov   ecx,eax
   shl   ecx,1
   rcl   BYTE [sign1],1
;   bswap ecx                 ; exponent to CL
   shr   ecx,24
   mov   BYTE [exp1],cl
   and   eax,0x007FFFFF
   bts   eax,23              ; set bit 23 for true fraction in EAX

   mov   ecx,ebx
   shl   ecx,1
   rcl   BYTE [sign2],1
;   bswap ecx                 ; exponent to CL
   shr   ecx,24
   mov   BYTE [exp2],cl
   and   ebx,0x007FFFFF
   bts   ebx,23              ; set bit 23 for true fraction in EBX

   mov   cl,BYTE [sign1]
   xor   cl,BYTE [sign2]
   mov   BYTE [signdiff],cl  ; flag to indicate sign difference

   ret

;  ----------------------------------------------
; |  Multiplication                              |
;  ----------------------------------------------
flmult:
   test  eax,eax
   jnz   .m1
   ret                  ; A was 0, so return with A=0 as result
.m1:
   test  ebx,ebx
   jnz   .m2
   mov   eax,ebx
   ret                  ; B was 0, so return with A=0 as result

.m2:
   call  flunpack
   mov   cl,BYTE [exp1]
   add   cl,BYTE [exp2]
   sub   cl,126         ; correct for bias, and one bit after product
   mov   BYTE [exp1],cl

   mul   ebx            ; EAX * EBX -> EDX:EAX (64 bits)
; the fractions are lower 24-bits in EAX and EBX, so the required product
; is in the top 24 bits of the lower 48 bits of EDX:EAX:
;
;   EDX        EAX
; 63 .. 32 | 31 .. 0
;
;   47..32   31..24
; (16 bits) (8 bits)

   shl   edx,8
   bswap eax
   or    dl,al
   mov   eax,edx
   mov   cl,BYTE [signdiff]
   mov   BYTE [sign1],cl      ; correct result sign
   jmp   normalise      ; normalise, repack and return


;  ----------------------------------------
; | Division                               |
;  ----------------------------------------
fldiv:
   test  ebx,ebx
   jnz   .d1
   mov   eax,ebx
   stc
   ret                  ; B was 0, return with carry set (and A=0) to indicate error
.d1:
   test  eax,eax
   jnz   .d2
   ret                  ; A was 0, so return with A=0 as result
.d2:
   call  flunpack       ; extract sign, exponent and fraction
   mov   cl,BYTE [exp1]
   sub   cl,BYTE [exp2] ; exponent difference - should check for exponent overflow
   add   cl,127         ; add back bias (allowable range is: -126 .. +127)
   mov   BYTE [exp1],cl

; fractions stored in 24 bits: EAX / EBX
; aligned (shifted) to bit 31.
; result will be shifted into EDX over 32 bits, so no need to clear it first

   shl   eax,8
   shl   ebx,8
   mov   cx,33
   jmp   fldiv24start
fldiv24lp:
   rcl   edx,1          ; shift result left, taking in carry at bit 0
   shl   eax,1          ; shift dividend left
   jc    fldiv24subonly ; if carry, use bit for quotient to allow full divisor
fldiv24start:
   sub   eax,ebx        ; trial subtract divisor
   jnc   fldiv24norest  ; it goes - carry set for quotient bit
   add   eax,ebx        ; doesn't go - restore (add back)
   clc                  ; 0 for quotient bit
   jmp   fldiv24again
fldiv24subonly:
   sub   eax,ebx        ; subtract divisor: for when dividend overflows left (1 in top bit)
fldiv24norest:
   stc                  ; 1 for quotient bit
fldiv24again:
   loop  fldiv24lp

   mov   eax,edx
   shr   eax,8          ; use top 24 bits of result (truncating lower 8 bits, without rounding)

   mov   cl,BYTE [signdiff]
   mov   BYTE [sign1],cl      ; correct result sign
   jmp   normalise      ; normalise, repack and return

;  ----------------------------------------
.end:
