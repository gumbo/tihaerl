pub main

  cognew(@entry, 0)
  
dat

'64 bit x 64 bit -> 64 bit unsigned division
' Divides inH:L by in2:in3. Result is in outH:L
'Status: 32x32 works
'        64x32 works
'        64x64 works 

_div64
        cmp in2, #0 wz
  if_nz jmp #bigDivisor 'denom >= 2**32

        cmp inH, in3 wc
  if_nc jmp #wouldOverflow

        mov in2, in3

        call #_div

        mov outH, #0
 
        jmp #_div64_ret
        
wouldOverflow
        'First digit
        mov inH, #0
        mov inL, nH
        mov in2, dL

        call #_div

        mov q1, outL    'q1

        mov inH, #0
        mov inL, q1
        mov in2, dL

        call #_mult

        mov k, nH

        sub k, outL

        mov inH, k
        mov inL, nL
        mov in2, dL

        call #_div

        mov outH, q1

        jmp #_div64_ret

bigDivisor
       mov inH, dH
       mov inL, dL
       call #_nlz

       mov n, outL

       mov t1, n
       mov t2, dL
       mov t3, dH
_shl64_1
       shl t2, #1 wc
       rcl t3, #1
       djnz t1, #_shl64_1

       mov in2, t3      't3 is (v >> n) >> 32 (high word)

       mov inH, nH      'nH:L = u, inH:L = u >> 1
       mov inL, nL      '

       shr inH, #1 wc
       rcr inL, #1

       call #_div
       
       mov outH, #0     'q1 = outL       
       
_shl64_2
       shl outL, #1 wc  'outH:L = q0
       rcl outH, #1
       djnz n, #_shl64_2

       shl outL, #1 wc  'Save MSB of outL (bit 31, which moves to the LSB position)
       mov outL, outH
       rcl outL, #1
       
       cmp outL, #0 wz       
 if_z  jmp #_div64_ret 

        'TODO do the final correction part

_div64_ret ret                                    

'Divide inH:inL by in2, leaving quotient in inL, remainder in inH, and in2 unchanged.
'Precondition: inH < in2.
'From http://forums.parallax.com/forums/default.aspx?f=25&m=245998&g=246017#m246017
'By Phil Pilgrim

_div    mov   t1,#32     'Initialize loop counter.
_div_loop
        rcl   inL,#1 wc     'Rotate quotient bit in from carry,
        rcl   inH,#1 wc     '  and rotate dividend out to carry
   if_c sub   inH,in2        'in2 < carry:inH if carry set, so just subtract, leaving carry set.
  if_nc cmpsub inH,in2 wc     'Otherwise, use cmpsub to do the dirty work.
        djnz  t1,#_div_loop  'Back for more.
        rcl   inL,#1 wc     'Rotate last quotient bit into place, restoring original carry.
        mov outL, inL               
_div_ret    ret

'32x32 bit multiply
'Multiplies inL by in2 
'Gives a 64 bit result in outH:L
'Destroys t1
'STATUS:   Working
_mult
        mov t1, #0
        mov outH, #0
        mov outL, #0
        mov inH, #0

multLoop    cmp in2, #0 wz
   if_z jmp #_mult_ret

        shr in2, #1 wc
  if_nc jmp #multShft

        add outL, inL wc
        addx outH, inH

multShft
        shl inL, #1 wc   
        rcl inH, #1
        jmp #multLoop

_mult_ret ret

_nlz
        cmp inH, #0 wz
  if_z  mov inH, inL

        cmp inH, #0 wz
  if_z  mov outL, #0
  if_z  jmp #_nlz_ret

        'Now at least one bit is set in inH
        mov outL, #0
_nlz_loop
        shl inH, #1  wc
  if_nc add outL, #1
  if_c  jmp #_nlz_ret
        jmp #_nlz_loop

_nlz_ret ret

nH LONG $7_6250      'numerator (dividend) 
nL LONG $A811_75CB

dH LONG $0000_00     'denominator (divisor)
dL LONG $ABCDEF

inH res 1
inL res 1
in2 res 1
outH res 1
outL res 1
t1 res 1
t2 res 1
t3 res 1

t4 res 1
t5 res 1
k res 1
q0 res 1
q1 res 1
n res 1
uH res 1
uL res 1
v1 res 1