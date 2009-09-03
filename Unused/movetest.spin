PUB main
 ina[10] := 1    
  cognew(@entry, 0)
DAT
entry
        or dira, stepPin
        or dira, dirPin
        andn outa, stepPin
        andn outa, dirPin

turnAround
        mov i, #0
        xor dira, dirPin

loop    cmp i, iterations wz
   if_z jmp #turnAround     
        
        'Start stepping sequence
        or  dira, stepPin                      'Make step low (output = yes)         
        waitcnt cntVal, highWaitTime            'Wait for the low pulse time (if not first iteration)
        and dira, stepPin                       'Inside high pulse                
        waitcnt cntVal, lowWaitTime                                      
        
        jmp #loop

dir LONG 0
i LONG 0        
iterations LONG 2000        
highWaitTime LONG 1200
lowWaitTime LONG 80000
dirPin LONG 1 << 4
stepPin LONG 1 << 5
cntVal res 1   