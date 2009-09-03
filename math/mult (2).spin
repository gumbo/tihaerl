var long p[4]
pub mainspin

  buf[0] := $EF54_37FD
  buf[1] := $FF99_8967
  buf[2] := 0
  buf[3] := 0
  buf[4] := $FFFF_EEEE

  cognew(@main,@buf)
dat
'32x32 bit multiply
'Multiplies mcandL by mplier 
'Gives a 64 bit result in valH:L
'STATUS:   Working
main
        mov ptr, par
        rdlong mcandL, ptr
        add ptr, #4
        rdlong mplier, ptr

        mov t1, #0
        mov valH, #0
        mov valL, #0
        mov mcandH, #0

loop    cmp mplier, #0 wz
   if_z jmp #done

        shr mplier, #1 wc
  if_nc jmp #mult

        add valL, mcandL wc
        addx valH, mcandH

mult    shl mcandL, #1 wc   
        rcl mcandH, #1
        jmp #loop

done    mov ptr, par
        add ptr, #8
        wrlong valH, ptr
        add ptr, #4
        wrlong valL, ptr
                     
don   jmp #don


mcandH res 1
mcandL res 1
mplier res 1
valH res 1
valL res 1
ptr res 1
t1 res 1
t2 res 1
t3 res 1
t4 res 1
buf     LONG 0[10] 