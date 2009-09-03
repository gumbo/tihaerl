var long p[3]
pub mainspin

  buf[0] := $0000_0000  
  buf[1] := $0203_69CD
  buf[2] := $0000_0000
  buf[3] := $0000_0003
  
  cognew(@main,@buf)
dat
'Perform a 64 bit x 64 bit --> 64 bit unsigned division
'Restoring divison algorithm from Hacker's Delight (http://www.hackersdelight.org/HDcode/divluh.c)
'Input: numH:L    numerator   (dividend)
'       denomH:L      denominator (divisor)
'Output outL     quotient
'STATUS:      Working 

main
        mov ptr, par
        rdlong numH, ptr
        add ptr, #4
        rdlong numL, ptr
        add ptr, #4 
        rdlong denomH, ptr
        add ptr, #4
        rdlong denomMH, ptr
        
        mov outH, #0
        mov outL, #0
        mov remML, numH
        mov remL, numL

        mov denomML, #0
        mov denomL, #0

        mov i, #64

loop
        sub remL, denomL wc
        subx remML, denomML wc
        subx remMH, denomMH wc
        subx remH, denomH

        cmp remL, #0 wc
        cmpx remML, #0 wc
        cmpx remMH, #0 wc
        cmpx remH, #0 wc

   if_c jmp #restore

        shl outL, #1 wc
        rcl outH, #1
        or outL, #1

        jmp #endif

restore add remL, denomL wc
        addx remML, denomML wc
        addx remMH, denomMH wc
        addx remH, denomH

        shl outL, #1 wc
        rcl outH, #1

endif   shr denomH, #1 wc
        rcr denomMH, #1 wc
        rcr denomML, #1 wc
        rcr denomL, #1
                
        djnz i, #loop             
                                                           
done    jmp #done

numH res 1
numL res 1
denomH res 1
denomMH res 1
denomML res 1
denomL res 1
remH res 1
remMH res 1
remML res 1
remL res 1
outH res 1
outL res 1
xH res 1      'Temporary 64 bit register
xL res 1
t1 res 1
t2 res 1
t3 res 1
ptr res 1
i res 1

buf     long                  0[10]