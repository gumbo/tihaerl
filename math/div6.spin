pub main
cognew(@entry, 0)

dat
entry
        call #_div
done    jmp #done                

'Divide inH:inL by in2, leaving quotient in inL, remainder in inH, and in2 unchanged.
'Precondition: inH < in2.

_div    mov   i,#32     'Initialize loop counter.
_div_loop
        rcl   inL,#1 wc     'Rotate quotient bit in from carry,
        rcl   inH,#1 wc     '  and rotate dividend out to carry
   if_c sub   inH,in2        'in2 < carry:inH if carry set, so just subtract, leaving carry set.
  if_nc cmpsub inH,in2 wc     'Otherwise, use cmpsub to do the dirty work.
        djnz  i,#_div_loop  'Back for more.
        rcl   inL,#1 wc     'Rotate last quotient bit into place, restoring original carry.
        mov outL, inL               
_div_ret    ret

inH LONG $1268e0  
inL LONG $9a9cd772
in2 LONG $abcdef12
outL res 1
i res 1