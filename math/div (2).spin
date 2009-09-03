var long p[3]
pub mainspin

  buf[0] := $72  
  buf[1] := $88D7_76B6
  buf[2] := $0000_AAAA
  buf[3] := $FFFF_EEEE
  
  cognew(@main,@buf)
dat
'Perform a 64 bit x 32 bit --> 32 bit unsigned division
'Restoring divison algorithm from Hacker's Delight (http://www.hackersdelight.org/HDcode/divluh.c)
'Input: x:y    numerator   (dividend)
'       z      denominator (divisor)
'Output y     quotient
'       x     remainder
'STATUS:      Working 
main
        mov ptr, par
        rdlong x, ptr
        add ptr, #4
        rdlong y, ptr
        add ptr, #4 
        rdlong z, ptr

loop    mov t, x
        shr t, #31
        
        shl y, #1 wc    'shift (x:y) left one
        rcl x, #1
        
        mov t1, x       '(x|t) >= z
        or t1, t

        cmp z, t1 wc, wz
if_c_or_z sub x, z      'subtract if we can
if_c_or_z add y, #1     'set quotient bit

        djnz i, #loop        

        mov ptr, par
        wrlong x, ptr
        add ptr, #4
        wrlong y, ptr
        add ptr, #4 
        wrlong z, ptr
                                          
done    jmp #done

x LONG 0
y LONG 0
z LONG 0
t LONG 0
i LONG 32
t1 res 1
ptr res 1

buf     long                  0[10]