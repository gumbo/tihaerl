var long p[3]
pub mainspin

  buf[0] := $1268e0  
  buf[1] := $9a9cd772
  buf[2] := $0
  buf[3] := $abcdef12
  
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
        rdlong denomL, ptr

        mov outH, #0
        mov outL, #0
        mov remH, #0
        mov remL, #0
        
        mov i, #64

loop
        shl numL, #1 wc
        rcl numH, #1 wc

        rcl remL, #1 wc
        rcl remM, #1 wc        
        rcl remH, #1

        shl outL, #1 wc 'Q<<1 to save the carry from the subtraction
        rcl outH, #1

        sub remL, denomL wc
        subx remM, denomH wc
        subx remH, #0 wc

        muxnc outL, #1  'Carry bit is just shifted 64 times                                                     

  if_nc  jmp #endif

        add remL, denomL wc
        addx remM, denomH wc
        addx remH, #0

endif   djnz i, #loop              
                                                  
done    jmp #done

numH res 1
numL res 1
denomH res 1
denomL res 1
remH res 1    '128 bit remainder
remM res 1
remL res 1
outH res 1
outL res 1
xH res 1      '128 bit temporary
xMH res 1
xML res 1
xL res 1
t1 res 1
t2 res 1
t3 res 1
ptr res 1
i res 1

buf     long                  0[10]