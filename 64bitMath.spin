CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000
OBJ
  ser : "FullDuplexSerial"
VAR
  long params[4]
  long id

PUB main
  ser.start(31, 30, 0, 57600)
  
  start
  ser.dec(calculatePathLength(8000, 4000, 0))

  ser.tx(".")
  ser.tx(".")
  ser.tx(".")
    
  ser.dec(calcVelocity(10000, 4000))

  repeat
PUB start
  params[3] := 0

  id := cognew(@entry, @params)

PUB stop
  if (id <> -1)
    cogstop(id)
    params[3] := 0 
  
PUB calculatePathLength(x, y, z)
  params[0] := x
  params[1] := y
  params[2] := z

  params[3] := 1

  repeat while params[3] == 1

  return params[0]

PUB calcVelocity(vel, dist)
  params[0] := vel
  params[1] := dist

  params[3] := 2

  repeat while params[3] == 2

  return params[0]
  
DAT
        org 0
        
entry   mov t1, PAR
        mov p1HubAddr, t1
        add t1, #4
        mov p2HubAddr, t1
        add t1, #4
        mov p3HubAddr, t1
        add t1, #4
        mov statusHubAddr, t1        

waitLoop
        rdlong cogStatus, statusHubAddr
        cmp cogStatus, #1 wz
   if_z mov cogStatus, #3     
   if_z call #calcPathLength
        cmp cogStatus, #2 wz
   if_z mov cogStatus, #3     
   if_z call #calcVel

        cmp cogStatus, #3 wz  
   if_z mov cogStatus, #0
   if_z wrlong cogStatus, statusHubAddr
        
        jmp #waitLoop

calcPathLength
        rdlong inX, p1HubAddr
        rdlong inY, p2HubAddr
        rdlong inZ, p3HubAddr

        shl inX, #8
        shl inY, #8
        shl inZ, #8

        'x*x
        mov inL, inX
        mov in2, inX
        call #_mult
        mov xtH, outH
        mov xtL, outL

        'y*y
        mov inL, inY
        mov in2, inY
        call #_mult
        mov ytH, outH
        mov ytL, outL

        'z*z
        mov inL, inZ
        mov in2, inZ
        call #_mult
        mov ztH, outH
        mov ztL, outL

        'x + y + z
        mov inH, xtH
        mov inL, xtL

        add inH, ytH  wc
        addx inL, ytL

        add inH, ztH  wc
        addx inL, ztL

        call #_sqrt

        mov pathLength, outL

        wrlong pathLength, p1HubAddr        

calcPathLength_ret ret

calcVel
        rdlong inL, p1HubAddr
        rdlong in2, p2HubAddr

        shl inL, #8
        shl in2, #8
        
        call #_mult

        mov inH, outH
        mov inL, outL
        mov in2, pathLength
        call #_div

        'Add 0.5 and truncate
        add outL, #80
        shr outL, #8

        wrlong outL, p1HubAddr

calcVel_ret ret
                
                    
'Begin 64 bit math routines
'-----------------------------------------------
'32x32 bit multiply
'Multiplies inL by in2 
'Gives a 64 bit result in outH:L
'Destroys t1
'STATUS:   Working
_mult
        mov t1, #0
        mov outH, #0
        mov outL, #0
        mov inH, #0

        'See if we will get 0 (a common case)
        cmp inL, #0 wz
  if_z  jmp #_mult_ret
        cmp in2, #0 wz
  if_z  jmp #_mult_ret              

multLoop    cmp in2, #0 wz      'At most 32 iterations
   if_z jmp #_mult_ret

        shr in2, #1 wc
  if_nc jmp #multShft

        add outL, inL wc
        addx outH, inH

multShft
        shl inL, #1 wc   
        rcl inH, #1
        jmp #multLoop

_mult_ret ret


'64 bit x 64 bit -> 64 bit unsigned division
'Divides inH:L by in2:in3. Result is in outH:L
'From hacker's delight: divDouble.c
'Status: 32x32 works
'        64x32 works
'        64x64 works 

_div64
        mov nH, inH
        mov nL, inL
        mov dH, in2
        mov dL, in3
        
        cmp dH, #0 wz
  if_nz jmp #bigDivisor 'denom >= 2**32

        cmp nH, dL wc
  if_nc jmp #wouldOverflow

        mov inH, nH
        mov inL, nL
        mov in2, dL

        call #_div

        mov outH, #0
 
        jmp #_div64_ret
        
wouldOverflow
        'First digit
        mov inH, #0
        mov inL, nH
        mov in2, dL

        call #_div

        mov t1, outL    'q1

        mov inH, #0
        mov inL, t1
        mov in2, dL

        call #_mult

        mov t2, nH

        sub t2, outL

        mov inH, t2
        mov inL, nL
        mov in2, dL

        call #_div

        mov outH, t1

        jmp #_div64_ret

bigDivisor
       mov inH, dH
       mov inL, dL
       call #_nlz

       mov t4, outL     't4 = n

       mov t1, t4
       mov t2, dL
       mov t3, dH
_shl64_1
       shl t2, #1 wc
       rcl t3, #1
       djnz t1, #_shl64_1

       mov in2, t3      't3 is (v >> n) >> 32 (high word)

       mov inH, nH      'nH:L = u, inH:L = u >> 1
       mov inL, nL      '

       shr inH, #1 wc
       rcr inL, #1

       call #_div
       
       mov outH, #0     'q1 = outL       
       
_shl64_2
       shl outL, #1 wc  'outH:L = q0
       rcl outH, #1
       djnz t4, #_shl64_2

       shl outL, #1 wc  'Save MSB of outL (bit 31, which moves to the LSB position)
       mov outL, outH
       rcl outL, #1
       
       cmp outL, #0 wz       
 if_z  jmp #_div64_ret 

        'TODO do the final correction part

_div64_ret ret                                    

'Divide inH:inL by in2, leaving quotient in inL, remainder in inH, and in2 unchanged.
'Precondition: inH < in2.
'From http://forums.parallax.com/forums/default.aspx?f=25&m=245998&g=246017#m246017
'By Phil Pilgrim

_div    mov   t1,#32     'Initialize loop counter.
_div_loop
        rcl   inL,#1 wc     'Rotate quotient bit in from carry,
        rcl   inH,#1 wc     '  and rotate dividend out to carry
   if_c sub   inH,in2        'in2 < carry:inH if carry set, so just subtract, leaving carry set.
  if_nc cmpsub inH,in2 wc     'Otherwise, use cmpsub to do the dirty work.
        djnz  t1,#_div_loop  'Back for more.
        rcl   inL,#1 wc     'Rotate last quotient bit into place, restoring original carry.
        mov   outL, inL               
_div_ret    ret

'Divide inH:inL by in2 (signed), leaving quotient in inL, remainder in inH, and in2 unchanged.
'Precondition: inH < in2.
'From http://forums.parallax.com/forums/default.aspx?f=25&m=245998&g=246017#m246017
'By Phil Pilgrim

_sdiv    mov   t1,#32     'Initialize loop counter.
         rol   in2, #1 wc 'If in2 is negative, then strip off the sign bit and preserve it in the carry flag
         shr   in2, #1    'Fixup our divisor
_sdiv_loop
        rcl   inL,#1 wc     'Rotate quotient bit in from carry,
        rcl   inH,#1 wc     '  and rotate dividend out to carry
   if_c sub   inH,in2        'in2 < carry:inH if carry set, so just subtract, leaving carry set.
  if_nc cmpsub inH,in2 wc     'Otherwise, use cmpsub to do the dirty work.
        djnz  t1,#_sdiv_loop  'Back for more.
        rcl   inL,#1 wc     'Rotate last quotient bit into place, restoring original carry.
        mov   t1,  #0
   if_c subs  t1, inL      'Add back our sign bit              
_sdiv_ret    ret
                             
'Compute a rounded integer square root 64 bits -> 32 bits
'Input inH:inL
'Output outL
'Destroys t1 - t7
'Renaming group: t1
'         sum: t2
'         diff: t3    
'         iter: t4
'         val: t5              
'STATUS Working

_sqrt
        mov t5, inH
        mov t1, #16
        mov outL, #0
        mov t2, #0
        mov t3, #0
        mov t4, #2

'2 iterations, one for each long        
iterLoop        

'16 iterations per time        
sqrtLoop
        shl t2, #1     't2=t2<<1;
        add t2, #1     't2+=1;

        shl t3, #2    't3 = t3 << 2
        
        't3+=(t5>>(t1*2))&3;
        mov t6, t5
        mov t7, t1
        sub t7, #1   '16 based   
        shl t7, #1   't1 * 2
        shr t6, t7
        and t6, #3
        add t3, t6

        shl outL, #1  'Make room for new result bit        
        cmp t2, t3 wc, wz 'if (t2>t3) then !c!z
if_c_or_z jmp #sqrtElse        
        'Difference is not changed, and this bit is a 0
        'in the result. We just correct the t2.
        sub t2, #1
        jmp #sqrtEndif
                  
sqrtElse    'Set this bit
        or outL, #1
        sub t3, t2   't3-=t2
        add t2, #1     't2 += 1

sqrtEndif   djnz t1, #sqrtLoop
        
        mov t5, inL
        mov t1, #16

        djnz t4, #iterLoop
                                           
_sqrt_ret ret

'Count the number of leading 0s in the 64 bit dword
'inH:L
'Number is in outL
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


p1HubAddr        res 1
p2HubAddr        res 1        
p3HubAddr        res 1
statusHubAddr   res 1
cogStatus       res 1
inX             res 1
inY             res 1
inZ             res 1

pathLength      res 1

'Temporaries
inH             res 1
inL             res 1
in2             res 1
in3             res 1
outH            res 1
outL            res 1
nH              res 1
nL              res 1
dH              res 1
dL              res 1
t1              res 1
t2              res 1
t3              res 1
t4              res 1
t5              res 1
t6              res 1
t7              res 1

xtH             res 1
xtL             res 1
ytH             res 1
ytL             res 1                  
ztH             res 1
ztL             res 1