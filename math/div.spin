var long p[3]
pub mainspin

  buf[0] := $1268e0  
  buf[1] := $9a9cd772
  buf[2] := $abcdef12
  buf[3] := $FFFF_EEEE
  
  cognew(@main,@buf)
dat
'Perform a 64 bit inH 32 bit --> 32 bit unsigned division
'Restoring divison algorithm from Hacker's Delight (http://www.hackersdelight.org/HDcode/divluh.c)
'Input: inH:inL    numerator   (dividend)
'       in2      denominator (divisor)
'Output outL     quotient
'STATUS:      Working 
main
        mov ptr, par
        rdlong inH, ptr
        add ptr, #4
        rdlong inL, ptr
        add ptr, #4 
        rdlong in2, ptr

        mov t3, #32

loop    mov t1, inH
        shr t1, #31
        
        shl inL, #1 wc    'shift (inH:inL) left one
        rcl inH, #1
        
        mov t2, inH       '(inH|t) >= in2
        or t2, t1

        cmp in2, t2 wc, wz
if_c_or_z sub inH, in2      'subtract if we can
if_c_or_z add inL, #1     'set quotient bit

        djnz t3, #loop        

        shr in2, #1
        cmp inH, in2 wc   'inH is remainder    if (remainder >= divisor / 2) then round  
  if_nc add inL, #1      
        mov outL, inL
                                                  
done    jmp #done

inH res 1
inL res 1
in2 res 1
outL res 1
t1 res 1
t2 res 1
t3 res 1
ptr res 1

buf     long                  0[10]