var long p[3]
pub mainspin          
  buf[0] :=  $0024_D1C1  
  buf[1] := $3539_AEE4
  buf[2] := $0000_AB
  buf[3] := $CDEF_1234
  
  cognew(@main,@buf)
dat
'Perform a 64 bit x 64 bit --> 64 bit unsigned division
'Restoring divison algorithm from Hacker's Delight (http://www.hackersdelight.org/HDcode/divluh.c)
'Input: numH:L    numerator   (dividend)
'       denomH:L      denominator (divisor)
'Output outL     quotient
'STATUS:      Working 

main
        mov q0, #0
        mov q1, #0        

        mov i, #128
        
{
http://maven.smith.edu/~thiebaut/ArtOfAssembly/CH09/CH09-4.html#HEADING4-99
Quotient := Dividend;
Remainder := 0;
for i:= 1 to NumberBits do

        Remainder:Quotient := Remainder:Quotient SHL 1;
        if Remainder >= Divisor then

                Remainder := Remainder - Divisor;
                Quotient := Quotient + 1;

        endif
endfor
}

        mov q0, n0
        mov q1, n1
        mov q2, n2
        mov q3, n3
        mov r0, #0
        mov r1, #0
        mov r2, #0
        mov r3, #0
        
loop    shl q0, #1 wc
        rcl q1, #1 wc
        rcl q2, #1 wc
        rcl q3, #1 wc
        rcl r0, #1 wc
        rcl r1, #1 wc
        rcl r2, #1 wc
        rcl r3, #1 wc 

        'Divisor <= Remainder: c or z are set
        cmp r0, d0 wc, wz
        cmpx r1, d1 wc, wz        
        cmpx r2, #0 wc, wz
        cmpx r3, #0 wc, wz

if_c_or_z jmp #notTrue

        sub r0, d0 wc, wz
        subx r1, d1 wc, wz        
        subx r2, #0 wc, wz
        subx r3, #0 wc, wz

        add q0, #1

notTrue djnz i, #loop        
                                                          
done    jmp #done

'128 bit x 64 bit -> 64 bit division
n3 LONG 0   'High word
n2 LONG 0
n1 LONG $0024_D1C1      'numerator (dividend) 
n0 LONG $3539_AEE4

d1 LONG $0000_AB     'denominator (divisor)
d0 LONG $CDEF_1234

r3 res 1
r2 res 1
r1 res 1
r0 res 1

q0 res 1
q1 res 1
q2 res 1
q3 res 1

x3 res 1
x2 res 1      'Temporary 64 bit register
x1 res 1
x0 res 1


t1 res 1
t2 res 1
t3 res 1
ptr res 1
i res 1

buf     long                  0[10]