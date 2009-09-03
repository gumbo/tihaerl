pub main
  cognew(@entry, 0)
dat
entry
        mov inH, #0
        mov inL, a
        call #_nlz

        mov oa, outL

        mov inH, #0
        mov inL, b
        call #_nlz

        mov ob, outL

        mov inH, #0
        mov inL, c
        call #_nlz

        mov oc, outL

done    jmp #done        
        
_nlz
        cmp inH, #0 wz
  if_z  mov inH, inL

        cmp inH, #0 wz
  if_z  mov outL, #0
  if_z  jmp #_nlz_ret

        'Now at least one bit is set in inH
        mov outL, #0
_nlz_loop
        shl inH, #1  wc
  if_nc add outL, #1
  if_c  jmp #_nlz_ret
        jmp #_nlz_loop

_nlz_ret ret

a LONG $3
b LONG $FFFFFFFF
c LONG $3FFFFFFF
inH res 1
inL res 1
outL res 1

oa res 1
ob res 1
oc res 1