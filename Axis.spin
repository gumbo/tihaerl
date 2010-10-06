CON
  GoFlagOffset     = 0
  MovingFlagOffset = 1
  StepPinOffset    = 2
  DirPinOffset     = 3
  LimitPinOffset   = 4
  FaultPinOffset   = 5
  AccelOffset      = 6
  MaxRateOffset    = 7
  CurPosOffset     = 8
  ReqPosOffset     = 9

  Ramp_Idle      = 0
  Ramp_Up        = 1
  Ramp_Max       = 2 
  Ramp_Down      = 3
  Ramp_Last      = 4

VAR
  long moving_flag              'TRUE if we haven't finished moving
  long axisData[15]
  long clockFreq  
PUB init(stepPinNum, dirPinNum, limitPinNum, faultPinNum, goflagAddr)

    longfill(@axisData, $0, 10)
    
    axisData[GoFlagOffset]     := goflagAddr
    axisData[MovingFlagOffset] := @moving_flag

    axisData[StepPinOffset]    := stepPinNum
    axisData[DirPinOffset]     := dirPinNum
    axisData[FaultPinOffset]   := faultPinNum
    axisData[LimitPinOffset]   := limitPinNum

    axisData[CurPosOffset]     := 0

    clockFreq := clkFreq

    moving_flag   := FALSE
     
    cognew(@entry, @axisData)

PUB isMoving
    return moving_flag == 0
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

        rdlong goFlagHubAddr, hubAddr                'Position 0
        add hubAddr, #4
        rdlong moveFlagHubAddr, hubAddr
        add hubAddr, #4
        rdlong stepPin, hubAddr
        add hubAddr, #4                                         
        rdlong dirPin, hubAddr                                  
        add hubAddr, #4
        rdlong limitPin, hubAddr
        add hubAddr, #4
        rdlong faultPin, hubAddr
        add hubAddr, #4
        
        mov accelHubAddr, hubAddr                            
        add hubAddr, #4
        mov maxRateAddr, hubAddr
        add hubAddr, #4
        mov curPosHubAddr, hubAddr                           
        add hubAddr, #4
        mov reqPosHubAddr, hubAddr
        add hubAddr, #4       

        shl stepPinMask, stepPin
        shl dirPinMask, dirPin
        shl limitPinMask, limitPin
        shl faultPinMask, faultPin
        or  limitPinMask, faultPinMask

        or dira, stepPinMask                       'Enable step and dir as outputs
        or dira, dirPinMask
        andn outa, stepPinMask                     'And set them low
        andn outa, dirPinMask

        andn dira, limitPinMask                    'Error pins are inputs

wait
        rdlong go_flag, goFlagHubAddr wz           'This value is non-zero if we are supposed to go
   if_z jmp #wait

        'Begin configuration. We want this step to always take the same amount of
        'time regardless of the path through it. So, sync to some larger cnt value
        'This also ensures we wait 2us for dir to latch
        mov cfgSyncCnt, configureDelay
        add cfgSyncCnt, cnt
        call #_configureMove
        waitcnt cfgSyncCnt, #1

        'Start moving!
        jmp #startMove                              'signal to start

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

        'Monitor when to switch states based on steps, and
        'also monitor limit switch and fault line
monitorLoop
        mov ctr, one_ms_delay
monitorWait
        cmp nextTransition, PHSB wz
  if_z  jmp nextState
        test INA, limitPin wz                  'Assumes that limit pin goes high when active
  if_nz jmp #stopState
        djnz ctr, #monitorWait                 'Loop for ~1ms, minus processing time

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
        {
              TODO verify we are getting in this state and properly
              clearing the right values
              verify we get into this state w/o any configuration,
              nothting to do, etc
        }
        wrlong curPos, curPosHubAddr            'Update the position
        mov    go_flag, #0
        wrlong go_flag,   goFlagHubAddr             'The first axis to finish will clear the go flag after they have all started
        mov    move_flag, #0
        wrlong move_flag, moveFlagHubAddr           'Mark that we're done moving

        jmp #wait

one_ms_delay   LONG 80_000      'TODO fix this count. This is clocks but we are doing loop cycles
configureDelay LONG 500         'TOD0 this needs to be 160 + instructions
stepPinMask    LONG 1
dirPinMask     LONG 1
limitPinMask   LONG 1
faultPinMask   LONG 1

cfgSyncCnt    res 1

posDelta      res 1
hubAddr       res 1
stepPin       res 1
dirPin        res 1
limitPin      res 1
faultPin      res 1

go_flag       res 1
move_flag     res 1

curPos        res 1
reqPos        res 1
cntVal        res 1

ctr            res 1

currentState res 1
nextState res 1
nextTransition res 1
 
goFlagHubAddr   res 1
moveFlagHubAddr res 1
curPosHubAddr   res 1
reqPosHubAddr   res 1
accelHubAddr    res 1
decelHubAddr    res 1
maxRateAddr     res 1

maxVelocity res 1
accelRate res 1
midPoint res 1
length res 1

delta res 1

        FIT 496
        
