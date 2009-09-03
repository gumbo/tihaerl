pub main
  cognew(@entry, 0)

dat

entry

{
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
        mov r0, #0
        mov r1, #0

        mov i, #64
loop            
        shl q0, #1 wc
        rcl q1, #1 wc
        rcl r0, #1 wc
        rcl r1, #1 wc
        rcl r2, #1

        cmp r0, d0  wc
        cmpx r1, d1 wc 
        cmpx r2, #0 wc

 if_c   jmp #endif

        sub r0, d0  wc
        subx r1, d1 wc 
        subx r2, #0 wc

        add q0, #1
                
 endif  djnz i, #loop

 done   jmp #done               
        

n1 LONG $1268e0  
n0 LONG $9a9cd772
d1 LONG 0
d0 LONG $abcdef12

a LONG $00ABCDEF
q1 LONG 0
q0 LONG 0      'quotient
b LONG $00ABCDEF
r0 res 1      'remainder
r1 res 1
r2 res 1

i res 1

  