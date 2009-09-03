CON
  StatusOffset  = 0          'Address
  GoBitOffset   = 1
  SetupBitOffset = 2
  ErrorBitOffset = 3
  StepPinOffset = 4
  DirPinOffset  = 5
  LowWaitOffset = 6          'Address
  AccelOffset   = 7          'Address
  DecelOffset   = 8          'Address
  MaxRateOffset = 9
  CurPosOffset  = 10         'Address
  ReqPosOffset  = 11         'Address  
  MathParamsOffset = 12      'Address

  'Math Array Offsets
  ClockFreqOffset = 0
  NewPosOffset = 1
  XDistOffset = 2
  YDistOffset = 3
  ZDistOffset = 4     
OBJ
  Constants : "Constants"
VAR
  long axisData[15]
  long mathParams[10]
  long clockFreq  
PUB init(stepPinNum, dirPinNum, statusAddr, goBitMask, setupBitMask, errorBitMask)

    longfill(@axisData, $0, 10)
    
    axisData[StatusOffset] := statusAddr
    axisData[GoBitOffset] := goBitMask
    axisData[SetupBitOffset] := setupBitMask
    axisData[ErrorBitOffset] := errorBitMask
    axisData[StepPinOffset] := stepPinNum
    axisData[DirPinOffset]  := dirPinNum
    axisData[MathParamsOffset] := @mathParams

    clockFreq := clkFreq
     
    cognew(@entry, @axisData)
PUB setRequestedPosition(reqPosition)
  axisData[ReqPosOffset] := reqPosition
PUB setCurrentPosition(curPosition)
  axisData[CurPosOffset] := curPosition
PUB getCurrentPosition
  return axisData[CurPosOffset]    
PUB setLowTime(timeInClocks)
  axisData[LowWaitOffset] := timeInClocks
PUB setAccelerationRate(accelRate)
  axisData[AccelOffset] := accelRate          
PUB setDecelerationRate(decelRate)
  axisData[DecelOffset] := decelRate
PUB setMaxStepRate(maxRate)
  axisData[MaxRateOffset] := maxRate
PUB configurePath(newPos, xDist, yDist, zDist)
  mathParams[ClockFreqOffset] := clockFreq
  mathParams[MaxRateOffset] := axisData[MaxRateOffset]
  mathParams[NewPosOffset] := newPos
  mathParams[XDistOffset] := xDist
  mathParams[YDistOffset] := yDist
  mathParams[ZDistOffset] := zDist
PUB home(limitPin)         
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

        mov homeBit, goBit
        or homeBit, errorBit
        or homeBit, setupBit

        mov waitHubAddr, hubAddr                             
        add hubAddr, #4
        mov accelHubAddr, hubAddr                            
        add hubAddr, #4
        mov decelHubAddr, hubAddr                            
        add hubAddr, #4
        mov maxRateAddr, hubAddr
        add hubAddr, #4
        mov curPosHubAddr, hubAddr                           
        add hubAddr, #4
        mov reqPosHubAddr, hubAddr
        add hubAddr, #4

        rdlong mathParamsAddr, hubAddr
        
        or dira, stepPin
        or dira, dirPin
        andn outa, stepPin
        andn outa, dirPin        

        jmp #wait


        { Move so that curPos==reqPos
          During the low pulse time, check that we can continue (status var in hub mem == 0)    
        }
mvsetup rdlong lowWaitTime, waitHubAddr
        rdlong reqPos, reqPosHubAddr
        rdlong curPos, curPosHubAddr
        
        cmp curPos, reqPos wz, wc
  if_z  jmp #done                               'nothing to do, resume waiting
  if_c  andn dira, dirPin                       'dir high if positive direction
  if_nc or   dira, dirPin                       'else dir low
  if_c  mov posDelta, #1                         'proper increment of curPos
  if_nc mov posDelta, negOne

        'Wait for dir to settle
        mov cntVal, #38
        add cntVal, cnt
        waitcnt cntVal, #1

        mov curStep, #0
        
        'Start stepping sequence
        or  dira, stepPin                      'Make step low (output = yes)
        mov cntVal, #20                         'initalize the timer 
        add cntVal, cnt                         '20 is ~min delay 
mvloop  cmp curPos, reqPos wz
  if_z  jmp #done                               'leave if equal                                       
        waitcnt cntVal, highWaitTime            'Wait for the low pulse time (if not first iteration)
        xor dira, stepPin                       'Inside high pulse
        adds curPos, posDelta
        add curStep, #1        
        waitcnt cntVal, #0                                      
        xor dira, stepPin                       'Transition to low pulse

        call #_determineAccelValue
'        mov   curVel, maxVel 
        call #_calcLowTime

        add cntVal, outL
                
        wrlong curPos, curPosHubAddr 
        rdlong status, statusHubAddr
        test status, #1 wz                      '1 is the main limit bit (See Constants.spin) 
  if_nz jmp #done                               'limits hit         
        jmp #mvloop

done    andn status, goBit                         'clear the go bit
        wrlong status, statusHubAddr        
        
wait    rdlong status, statusHubAddr        
        test status, goBit wz
  if_nz jmp #mvsetup                               'signal to start
        test status, setupBit wz
  if_z  jmp #wait
        call #_configurePath                        'Setup the appropriate numbers for this axis                      
        jmp #wait

'Determine which portion of the velocity trapezoid the current step falls on
'Return the velocity        
_determineAccelValue
        cmp curStep, fip wc
if_nc   jmp #cruiseVel

        mov inH, #0
        mov inL, accelVal
        mov in2, curStep
        call #_mult
        mov curVel, outL

        jmp #_determineAccelValue_ret

cruiseVel
        cmp curStep, sip wc
if_nc   jmp #decelVel

        mov curVel, maxVel

        jmp #_determineAccelValue_ret

decelVel
        mov inH, #0                             'Deceleration does not occur
        mov inL, decelVal
        mov in2, curStep
        call #_mult
        neg outL, outL
        adds outL, c

        mov curVel, outL                        

_determineAccelValue_ret ret

'New rate is in curVal
'Output is in outL
'Executes rateScaleFactor / curVel 
_calcLowTime

        mov inH, #0
        mov inL, rateScaleFactor
        mov in2, curVel
        call #_div

_calcLowTime_ret ret


' Calculates the correct pulse period based on the following formula:
'(clockFreq * axisLength) / pathLength
'Also configures the acceleration profile
'Retuns result in outL
_configurePath
        mov hubAddr, mathParamsAddr
        rdlong i4, hubAddr      'Clock freq      
        add hubAddr, #4
        rdlong reqPos, hubAddr  'New Position
        wrlong reqPos, reqPosHubAddr
        add hubAddr, #4
        rdlong i1, hubAddr      'X dist
        add hubAddr, #4
        rdlong i2, hubAddr      'Y dist
        add hubAddr, #4
        rdlong i3, hubAddr      'Z dist
        add hubAddr, #4
                
        'Calculate axis length
        rdlong curPos, curPosHubAddr
        mov in2, reqPos                         'in2 is the axisLength
        subs in2, curPos
        abs in2, in2

        mov inL, i4            
        call #_mult
        mov tH, outH
        mov tL, outL

        call #_calcPathLength  'puts length in outL
        mov pathLength, outL
        mov inH, tH
        mov inL, tL
        mov in2, outL
        
        call #_div
        mov rateScaleFactor, outL

        'Create the velocity profile information
readParams        
        rdlong accelVal, accelHubAddr
        rdlong decelVal, decelHubAddr
        rdlong maxVel,  maxRateAddr

        abs inL, decelVal
        add pathLength, #1
        mov in2, pathLength
        call #_mult
        mov c, outL

        mov inL, c              'c * accelVal
        mov in2, accelVal
        call #_mult

        mov inH, #0             ' (c * accelVal) / (accelVal - decelVal)
        mov inL, outL
        mov in2, accelVal
        add in2, decelVal
        call #_div

        cmp outL, maxVel wc
 if_nc  jmp #cruiseSpeedReached
        mov fip, outL
        mov sip, outL
        jmp #signal
        
cruiseSpeedReached
        mov inH, #0
        mov inL, maxVel
        mov in2, accelVal
        call #_div
        mov fip, outL

        mov inH, #0
        mov inL, maxVel
        subs inL, c
        abs inL, inL
        mov in2, decelVal
        call #_div
        mov sip, outL                
                
signal  andn status, setupBit                      'Signal we're done
        wrlong status, statusHubAddr    'Notify the Spin code

_configurePath_ret ret

_calcPathLength
        mov inL, i1
        mov in2, i1
        call #_mult
        mov t2, outL    't3:2 is the temporary 
        mov t3, outH
        mov inL, i2
        mov in2, i2
        call #_mult
        add t2, outL wc
        addx t3, outH
        mov inL, i3
        mov in2, i3
        call #_mult
        add t2, outL wc
        addx t3, outH

        mov inL, t2
        mov inH, t3
        call #_sqrt

_calcPathLength_ret ret                   

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
        mov outL, inL               
_div_ret    ret
                             
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

highWaitTime  LONG 1200
negOne        LONG -1

posDelta      res 1
hubAddr       res 1
stepPin       res 1
dirPin        res 1
lowWaitTime   res 1
goBit         res 1
setupBit      res 1
errorBit      res 1
homeBit       res 1

curPos        res 1
reqPos        res 1
cntVal        res 1
status        res 1

statusHubAddr res 1
curPosHubAddr res 1
reqPosHubAddr res 1
waitHubAddr   res 1
accelHubAddr  res 1
decelHubAddr  res 1
maxRateAddr   res 1
mathParamsAddr res 1

curVel res 1
rateScaleFactor res 1
fip res 1               'Velocity inflection points (where we switch to no accel)
sip res 1
maxVel res 1
curStep res 1
accelVal res 1
decelVal res 1
c res 1                 'Offset for decel line
pathLength res 1

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