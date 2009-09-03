pub main
  cognew(@entry, 0)

dat

entry                                   '         z c
        cmp zero, one wc, wz            '10 > 01  0 1 
        cmpx one, zero wc, wz
        
        cmp one, zero wc, wz            '11 > 00  0 1
        cmpx one, zero wc, wz
        
        cmp zero, zero wc, wz           '00 < 10  0 0
        cmpx zero, one wc, wz
        
        cmp one, one wc, wz             '11 > 10  0 1
        cmpx one, zero wc, wz

        cmp zero, zero wc, wz           '10 = 10  1 0      
        cmpx one, one wc, wz

        cmp one, zero wc, wz            '01 < 10  0 0     
        cmpx zero, one wc, wz


        mov a, #5 
zero LONG 0
one LONG  1
a res 1