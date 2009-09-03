var long p[4]
pub mainspin

  p[0] := $0000_734C
  p[1] := $C2F2_A521
  p[2] := 0
  p[3] := 0
  
  cognew(@main,@p)
dat
'Compute a rounded integer square root 64 bits -> 32 bits
'Input aH:aL
'Output rootL
'Destroys i, t1
'STATUS

main
        mov ptr, par
        rdlong aH, ptr
        add ptr, #4
        rdlong aL, ptr

        mov i, #32
loop    shl rootL, #1 wc        'root <<= 1
        rcl rootH, #1

        shl remL, #1 wc         'rem <<= 2
        rcl remH, #1
        shl remL, #1 wc
        rcl remH, #1

        mov t1, aH              'a >> 62. We simply shift the high long 30 bits
        shr t1, #30

        add remL, t1 wc         '(rem << 2) + (a >> 62)
        addx remH, #0

        shl aL, #1 wc         'a <<= 2
        rcl aH, #1
        shl aL, #1 wc
        rcl aH, #1

        add rootL, #1 wc        'root++
        addx rootH, #0

        cmp rootL, remL wc,wz   'if (root <= rem)
        cmpx rootH, remH wc,wz

if_nc_and_nz jmp #els

        sub remL, rootL wc      'rem -= root
        subx remH, rootH

        add rootL, #1 wc        'root++
        add rootH, #0

        jmp #endif
                        
els    sub rootL, #1 wc        'root--
        subx rootH, #0

endif   djnz i, #loop

        shr rootH, #1 wc
        rcr rootL, #1
                                          
done    jmp #done

aH LONG 0
aL LONG 0
remH LONG 0
remL LONG 0
rootH LONG 0
rootL LONG 0

t1 res 1

i res 1    
ptr res 1