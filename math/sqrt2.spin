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
'Output root
'Destroys i, t1, t2
'STATUS Working

main
        mov ptr, par
        rdlong aH, ptr
        add ptr, #4
        rdlong aL, ptr

        mov val, aH
        mov group, #16
        mov root, #0
        mov sum, #0
        mov diff, #0
        mov iter, #2

'2 iterations, one for each long        
iterLoop        

'16 iterations per time        
mainLoop
        shl sum, #1     'sum=sum<<1;
        add sum, #1     'sum+=1;

        shl diff, #2    'diff = diff << 2
        
        'diff+=(val>>(group*2))&3;
        mov t1, val
        mov t2, group
        sub t2, #1   '16 based   
        shl t2, #1   'group * 2
        shr t1, t2
        and t1, #3
        add diff, t1

        shl root, #1  'Make room for new result bit        
        cmp sum, diff wc, wz 'if (sum>diff) then !c!z
if_c_or_z jmp #els        
        'Difference is not changed, and this bit is a 0
        'in the result. We just correct the sum.
        sub sum, #1
        jmp #endif
                  
els    'Set this bit
        or root, #1
        sub diff, sum   'diff-=sum
        add sum, #1     'sum += 1

endif   djnz group, #mainLoop
        
        mov val, aL
        mov group, #16

        djnz iter, #iterLoop
                                           
done    jmp #done

aH LONG 0
aL LONG 0
group res 1
sum   res 1
diff  res 1
root res 1
iter res 1

t1 res 1
t2 res 1
val res 1

ptr res 1