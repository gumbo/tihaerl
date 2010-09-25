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
  UpdateLockID   = 11

  Ramp_Idle      = 0
  Ramp_Up        = 1
  Ramp_Max       = 2 
  Ramp_Down      = 3
  Ramp_Last      = 4     
     
OBJ
  Constants : "Constants"
  Serial    : "SerialMirror"
VAR
  long axisData[15]
  long clockFreq  
PUB init(stepPinNum, dirPinNum, limitPinNum, statusAddr, goBitMask, setupBitMask, errorBitMask, slockID)

    longfill(@axisData, $0, 10)
    
    axisData[StatusOffset] := statusAddr
    axisData[GoBitOffset] := goBitMask
    axisData[SetupBitOffset] := setupBitMask
    axisData[ErrorBitOffset] := errorBitMask
    axisData[StepPinOffset] := stepPinNum
    axisData[DirPinOffset]  := dirPinNum
    axisData[LimitPinOffset]  := limitPinNum
    axisData[UpdateLockID] := slockID

    axisData[CurPosOffset] := 0

    clockFreq := clkFreq
     
    cognew(@entry, @axisData)

PUB setRequestedPosition(reqPosition)
  axisData[ReqPosOffset] := reqPosition
PUB getRequestedPosition
  return axisData[ReqPosOffset]
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
        rdlong lockID, hubAddr
        add hubAddr, #4

        shl stepPinMask, stepPin
        shl dirPinMask, dirPin
        shl limitPinMask, limitPin
        

        or dira, stepPinMask
        or dira, dirPinMask
        andn outa, stepPinMask
        andn outa, dirPinMask        

        jmp #wait

wait    rdlong status, statusHubAddr        
        test status, setupBit wz
   if_z jmp #testGoBit             
        call #_configureMove                       'Setup the appropriate numbers for this axis    
acquireLockWait
        lockset lockID wc
   if_c jmp #acquireLockWait
        rdlong status, statusHubAddr
        andn status, setupBit
        wrlong status, statusHubAddr
        lockclr lockID
testGoBit        
        test status, goBit wz            
  if_nz jmp #startMove                              'signal to start
                      
        jmp #wait

_configureMove
        rdlong curPos, curPosHubAddr 
        rdlong reqPos, reqPosHubAddr

        rdlong accelRate, accelHubAddr 
        rdlong maxVelocity, maxRateAddr

        cmps curPos, reqPos wc, wz

   if_z mov nextTransition, #0
   if_z mov nextState, #stopState     
   if_z jmp #_configureMove_ret

   'This was c, second was nc            
  if_nc andn outa, dirPinMask                      '"Positive" direction (away from the motor)
   if_c or   outa, dirPinMask                      '"Negative" direction (towards the motor)

        call #wait2us

        mov length, curPos
        subs length, reqPos
        abs length, length

        {
              If we are going to have a "short" move then don't do acceleration,
              just turn on the timer and hit the stop state when necessary
              TODO moves of length 1 don't seem to do anything
              TODO how short is short?
        }

        cmp length, #50 wc, wz
if_c_or_z jmp #shortMove

        mov midPoint, length
        shr midPoint, #1

        'Start deceleration if we never hit the cruise state
        mov nextState, #decelState
        mov currentState, #accelState
        mov nextTransition, midPoint

        jmp #configureHW

shortMove
        mov nextState, #stopState
        mov currentState, #cruiseState
        mov nextTransition, length

configureHW
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

        'This is really the monitor loop
monitorLoop
        mov ctr, loopIterations
monitorWait
        cmp nextTransition, PHSB wz
  if_z  jmp nextState
'        test INA, limitPin wz                  'Assumes that limit pin goes high when active
'  if_nz jmp #stopState
        djnz ctr, #monitorWait                    'Loop for ~1ms, minus processing time

        jmp currentState
        
        'Accel State
accelState
        {
              Determine the amount that is left between FRQA and maxVelocity,
              and only increment that amount.  If we have reached this limit then
              C or Z will be set, otherwise we are still accelerating.
        }
        mov delta, maxVelocity
        sub delta, FRQA                          'delta = maxVelocity - FRQA
        max delta, accelRate wc, wz              'Limit accelRate to the amount left to go
        add FRQA, delta                          'Accelerate the timer frequency

        'Restart the wait loop if we are not done accelerating
if_nc_and_nz jmp #monitorLoop

        'Done accelerating, transition to the cruise state
        mov currentState, #cruiseState          'Jump to the cruise state if we've finished accelerating
        mov nextTransition, length              'We are going to get kicked out of cruise by the monitor loop
        sub nextTransition, PHSB                'At point (length - curStepCtr)
        add nextTransition, #1

        jmp #monitorLoop

decelState
        {
              Start out our decel with the same factor that the accel ended with
              This is so the velocity profile is identical
              delta may == accelRate

              TODO what about extremely small steps?
        }
        cmp delta, #0 wz                        'If delta is 0 then we hit the rate exactly
  if_nz sub FRQA, delta                         'Otherwise, make the first step smaller
  if_nz mov delta, #0                           'And don't check again

   if_z cmpsub FRQA, accelRate wz               'Decelerate
   if_z mov FRQA, accelRate                     'Make sure we don't stop completely (if accelRate == FRQA)
        mov nextState, #stopState               'We are going to stop if the monitor loop kicks us out
        mov currentState, #decelState           'Jump back to decel if 1ms expires
        mov nextTransition, length              'Stop when we've gone far enough

        jmp #monitorLoop

'No acceleration, just continue on at the same frequency until we hit the deceleration
'point
cruiseState
        jmp #monitorLoop

stopState
        mov CTRA, #0                            'Stop the step generator        
        cmps curPos, reqPos wc,wz
if_c_and_nz  adds curPos, PHSB
if_nc_and_nz subs curPos, PHSB
acquireLockStop
        lockset lockID wc
   if_c jmp #acquireLockStop     
        wrlong curPos, curPosHubAddr
        rdlong status, statusHubAddr
        andn status, goBit
        wrlong status, statusHubAddr
        lockclr lockID
                         
        jmp #wait


        
wait2us 'Wait ~2us for dir to settle
        mov cntVal, #160
        add cntVal, cnt
        waitcnt cntVal, #1
wait2us_ret ret        

loopIterations LONG 80_000      'TODO fix this count
stepPinMask   LONG 1
dirPinMask    LONG 1
limitPinMask  LONG 1 

posDelta      res 1
hubAddr       res 1
stepPin       res 1
dirPin        res 1
limitPin      res 1
goBit         res 1
setupBit      res 1
errorBit      res 1
lockID        res 1

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

delta res 1

        FIT 496
        
