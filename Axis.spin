CON
  StatusOffset   = 0          'Address
  GoBitOffset    = 1
  SetupBitOffset = 2
  ErrorBitOffset = 3
  StepPinOffset  = 4  
  DirPinOffset   = 5
  LimitPinOffset = 6
  AccelOffset    = 7
  MaxRateOffset  = 8
  CurPosOffset   = 9  
  ReqPosOffset   = 10

  Ramp_Idle      = 0
  Ramp_Up        = 1
  Ramp_Max       = 2 
  Ramp_Down      = 3
  Ramp_Last      = 4     
     
OBJ
  Constants : "Constants"
VAR
  long axisData[15]
  long clockFreq  
PUB init(stepPinNum, dirPinNum, limitPinNum, statusAddr, goBitMask, setupBitMask, errorBitMask)

    longfill(@axisData, $0, 10)
    
    axisData[StatusOffset] := statusAddr
    axisData[GoBitOffset] := goBitMask
    axisData[SetupBitOffset] := setupBitMask
    axisData[ErrorBitOffset] := errorBitMask
    axisData[StepPinOffset] := stepPinNum
    axisData[DirPinOffset]  := dirPinNum
    axisData[LimitPinOffset]  := limitPinNum

    axisData[CurPosOffset] := 0

    clockFreq := clkFreq
     
    cognew(@entry, @axisData)
PUB setRequestedPosition(reqPosition)
  axisData[ReqPosOffset] := reqPosition
PUB setCurrentPosition(curPosition)
  axisData[CurPosOffset] := curPosition
PUB getCurrentPosition
  return axisData[CurPosOffset]    
PUB setAccelerationRate(_accelRate) | freq
  _accelRate <<= 1 

  repeat 32                            'perform long division of a/b
    freq <<= 1
    if _accelRate => CLKFREQ
      _accelRate -= CLKFREQ
      freq++
                   
    _accelRate <<= 1
    
  axisData[AccelOffset] := freq
PUB setMaxStepRate(maxRate) | freq
  maxRate <<= 1 

  repeat 32                            'perform long division of a/b
    freq <<= 1
    if maxRate => CLKFREQ
      maxRate -= CLKFREQ
      freq++
                 
    maxRate <<= 1

  axisData[MaxRateOffset] := freq
DAT
        ORG 0
entry   mov hubAddr, PAR                        'HubAddr is the pointer into hub memory

        rdlong statusHubAddr, hubAddr                'Position 0        
        add hubAddr, #4
        rdlong goBit, hubAddr
        add hubAddr, #4
        rdlong setupBit, hubAddr
        add hubAddr, #4
        rdlong errorBit, hubAddr
        add hubAddr, #4
        rdlong stepPin, hubAddr                                 
        add hubAddr, #4                                         
        rdlong dirPin, hubAddr                                  
        add hubAddr, #4
        rdlong limitPin, hubAddr
        add hubAddr, #4
        
        mov accelHubAddr, hubAddr                            
        add hubAddr, #4
        mov maxRateAddr, hubAddr
        add hubAddr, #4
        mov curPosHubAddr, hubAddr                           
        add hubAddr, #4
        mov reqPosHubAddr, hubAddr
        add hubAddr, #4

        or dira, stepPin
        or dira, dirPin
        andn outa, stepPin
        andn outa, dirPin        

        jmp #wait

wait    rdlong status, statusHubAddr        
        test status, setupBit wz
  if_nz andn status, setupBit      
  if_nz call #_configureMove                       'Setup the appropriate numbers for this axis
  if_nz wrlong status, statusHubAddr
        test status, goBit wz
  if_nz andn status, goBit      
  if_nz jmp #startMove                              'signal to start
  if_nz wrlong status, statusHubAddr
                      
        jmp #wait

_configureMove
        rdlong curPos, curPosHubAddr 
        rdlong reqPos, reqPosHubAddr

        rdlong accelRate, accelHubAddr 
        rdlong maxVelocity, maxRateAddr


        cmps curPos, reqPos wc, wz

   if_z jmp #wait
                 
   if_c andn outa, dirPin                          '"Positive" direction (away from the motor)
  if_nc or   outa, dirPin                          '"Negative" direction (towards the motor)

'        call #wait2us

        mov length, curPos
        subs length, reqPos
        abs length, length
        mov midPoint, length
        shr midPoint, #1

        mov nextState, #decelState
        mov currentState, #accelState
        mov nextTransition, midPoint

        andn outa, stepPin

        mov FRQA, #0        
        mov FRQB, #1
        mov PHSA, #0
        mov PHSB, #0
        mov CTRA, #0
        mov CTRB, #0

        movi CTRA, #%0_00100_000   'NCO mode
        movi CTRB, #%0_01010_000   'POSEDGE detector

        movs CTRA, stepPin
        movs CTRB, stepPin
_configureMove_ret ret

startMove
        mov FRQA, accelRate
        
moveLoop
        mov ctr, loopIterations
accelWait                        
        cmp nextTransition, PHSB wz
  if_z  jmp nextState
        test INA, limitPin wz                  'Assumes that limit pin goes high when active
  if_nz jmp #stopState
        djnz ctr, #accelWait                    'Loop for ~1ms, minus processing time

        jmp currentState
        
        'Accel State
accelState                                                                             
        add FRQA, accelRate                     'Accelerate the timer frequency
        max FRQA, maxVelocity wc                'Make sure we don't go over the max velocity
  if_nc mov currentState, #cruiseState          'Jump to the cruise state if we've finished accelerating
  if_nc mov nextTransition, length              'We are going to get kicked out of cruise by the monitor loop
  if_nc sub nextTransition, PHSB                'At point (length - curStepCtr)

        jmp #moveLoop

decelState
        sub FRQA, accelRate                     'Decelerate
        mins FRQA, accelRate                     'Make sure we don't stop completely (or go negative)
        mov nextState, #stopState               'We are going to stop if the monitor loop kicks us out
        mov currentState, #decelState           'Jump back to decel if 1ms expires
        mov nextTransition, length              'Stop when we've gone far enough

        jmp #moveLoop

cruiseState
        jmp #moveLoop

stopState
        mov CTRA, #0                            'Stop the step generator        
        cmps curPos, reqPos wc
   if_c adds curPos, PHSB
  if_nc subs curPos, PHSB
        wrlong curPos, curPosHubAddr                         
        jmp #wait


        
wait2us 'Wait ~2us for dir to settle
        mov cntVal, #160
        add cntVal, cnt
        waitcnt cntVal, #1
wait2us_ret ret        

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


loopIterations LONG 80_000 

posDelta      res 1
hubAddr       res 1
stepPin       res 1
dirPin        res 1
limitPin      res 1
goBit         res 1
setupBit      res 1
errorBit      res 1

curPos        res 1
reqPos        res 1
cntVal        res 1
status        res 1

ctr            res 1

currentState res 1
nextState res 1
nextTransition res 1
 

statusHubAddr res 1
curPosHubAddr res 1
reqPosHubAddr res 1
accelHubAddr  res 1
decelHubAddr  res 1
maxRateAddr   res 1

maxVelocity res 1
accelRate res 1
midPoint res 1
length res 1

rampJmp res 1
rampState res 1

'Variables for 64 bit math stuff
inH res 1
inL res 1
in2 res 1
in3 res 1
nH res 1
nL res 1
dH res 1
dL res 1
outH res 1
outL res 1
t1 res 1
t2 res 1
t3 res 1
t4 res 1
t5 res 1
t6 res 1
t7 res 1
tH res 1
tL res 1

i1 res 1
i2 res 1
i3 res 1
i4 res 1
i5 res 1
i6 res 1

ptr res 1

        FIT 496