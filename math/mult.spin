var long p[4]
pub mainspin

  p[0] := $EF54_37FD
  p[1] := $FF99_8967
  
  cognew(@main,@p)
dat
'32x32 bit multiply
'Multiplies inL by in2 
'Gives a 64 bit result in outH:L
'Destroys t1
'STATUS:   Working
main
        mov ptr, par
        rdlong inL, ptr
        add ptr, #4
        rdlong in2, ptr

        mov t1, #0
        mov outH, #0
        mov outL, #0
        mov inH, #0

loop    cmp in2, #0 wz
   if_z jmp #done

        shr in2, #1 wc
  if_nc jmp #mult

        add outL, inL wc
        addx outH, inH

mult    shl inL, #1 wc   
        rcl inH, #1
        jmp #loop

done    jmp #done


inH res 1
inL res 1
in2 res 1
outH res 1
outL res 1
ptr res 1
t1 res 1 