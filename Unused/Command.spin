CON
   BUF_END = "."  'End of the buffer marker (this set of commands)
   MODE    = "@"  'Mode specifier (axes or extruders)

   EXTRUDER_MODE = "E"          'Extruder command mode
   AXES_MODE     = "A"          'Axes command mode
   CALIBRATION_MODE = "C"       'Axes calibration mode

   { Axes Mode commands }
   
   '' R<axis><steps per second, 0-9999>
   STEP_RATE = "R" ' Maximum number of steps per second
   
   ''A<axis><steps per second^2>  Acceleration amount - this value is added to the axis step rate 50 times per second
   ACCEL_RATE =  "A"
   
   ENABLE_DRIVES  = "E" 
   DISABLE_DRIVES = "D"
                                                    
   'Path mode definitions
   SMOOTH_CONTOURING  = "C"   ' Enable the use of splines for the next moves (calculated by the host)
   LINEAR      = "L"   ' Enable vector travel
   POSITIONING = "P"   ' Rapids
   
  {Path position definitions
    M<number of axes><axis>[+,-]<length, 0-32767>...}
   MOVEMENT =  "M" ' Next position in set
   X_AXIS   =  "X"
   Y_AXIS   =  "Y"
   Z_AXIS   =  "Z"


   { Extruder Mode commands }

   {Calibration Mode commands }

   ''H<axis>      Move to the home position
   HOME = "H"

   ''L<axis>      Move to the limit position
   LIMIT = "L"

   ''G<axis>      Return the current axis position counter
   GET_POS = "G"

  'Offsets for the shared data array in RAM
  AXIS_LEN = 7  
  STATUSOFF = 0 * 4
  CMDPTR = 1 * 4
  X_DATA = 2 * 4    
  Y_DATA = (X_DATA + AXIS_LEN) * 4
  Z_DATA = (Y_DATA + AXIS_LEN) * 4

  SignFlag      = $1
  ZeroFlag      = $2
  NaNFlag       = $8
OBJ 
PUB start(paramBufPtr)
  cognew(@init, paramBufPtr)
  
DAT
        ORG 0
        
init    mov hubBuf, par         'Init all of the hub memory pointers
        mov t1, hubBuf
        add t1, #STATUSOFF
        mov statusAddr, t1
        rdlong statusAddr, statusAddr
        mov t1, hubBuf
        add t1, #CMDPTR
        mov cmd, t1
        rdlong cmd, cmd         'Double dereference for some reason - if bugs appear, look here
        mov t1, hubBuf
        add t1, #X_DATA
        mov xAddr, t1
        mov t1, hubBuf
        add t1, #Y_DATA
        mov yAddr, t1
        mov t1, hubBuf
        add t1, #Z_DATA
        mov zAddr, t1
        
:check  rdlong status, statusAddr 
        test status, #1<<2wz
  if_nz andn status, #1 << 2              'Clear the new bit
  if_nz jmp #processCommand
        jmp #:check  
                
processCommand
:loop   rdbyte cmdChar, cmd
        add cmd, #1
        cmp cmdChar, #BUF_END wz
   if_z cogid t1
   if_z cogstop t1
        cmp cmdChar, #STEP_RATE wz
   if_z jmp #:stepRate
        cmp cmdChar, #ACCEL_RATE wz
   if_z jmp #:accelRate
        cmp cmdChar, #SMOOTH_CONTOURING wz
   if_z mov pathType, #0
        cmp cmdChar, #LINEAR wz
   if_z mov pathType, #1
        cmp cmdChar, #POSITIONING wz
   if_z mov pathType, #2
        cmp cmdChar, #MOVEMENT wz
   if_z jmp #:configMovement
        cmp cmdChar, #ENABLE_DRIVES wz
   if_z andn outa, enablePin
        cmp cmdChar, #DISABLE_DRIVES wz
   if_z or outa, disablePin        
        'subroutines return to top of loop
        jmp #:loop      'Try the next byte if all options fail
   
:stepRate
        rdbyte cmdChar, cmd
        mov t4, cmdChar
        add cmd, #1         
        call #atoi         
        cmp t4, #X_AXIS wz
   if_z mov xRate, t2 
        cmp t4, #Y_AXIS wz
   if_z mov yRate, t2
        cmp t4, #Z_AXIS wz
   if_z mov zRate, t2
        jmp #processCommand


:accelRate
        rdbyte cmdChar, cmd
        mov t4, cmdChar
        add cmd, #1         
        call #atoi         
        cmp t4, #X_AXIS wz
   if_z mov xAccel, t2   
        cmp t4, #Y_AXIS wz
   if_z mov yAccel, t2  
        cmp t4, #Z_AXIS wz
   if_z mov zAccel, t2
        jmp #processCommand
        
:configMovement
        rdbyte cmdChar, cmd
        mov t5, cmdChar
        sub t3, #"0"
        add cmd, #1
:cfglp  rdbyte t4, cmd
        add cmd, #1
        call #atoi         
        cmp t4, #X_AXIS wz
   if_z mov xDist, t2 
        cmp t4, #Y_AXIS wz
   if_z mov yDist, t2
        cmp t4, #Z_AXIS wz
   if_z mov zDist, t2
        djnz t5, #:cfglp
        cmp pathType, LINEAR wz
   if_z call #linearMovement
        cmp pathType, POSITIONING wz
   if_z call #rapidMovement 
        jmp #processCommand      'TODO process movement

'Configure the axes for a vectorized movement        
linearMovement
        'pathDist = sqrt(xDist^2 + yDist^2 + zDist^2)
        'rate = (rate * axisDist) / pathDist
        't4 = pathDistH
        't5 = pathDistL

        'Calculate path length
        mov param1L, xRate
        mov param2,  xRate
        call #mult
        mov t4, resultH
        mov t5, resultL

        mov param1L, yRate
        mov param2,  yRate
        call #mult
        add t4, resultH wc
        addx t5, resultL

        mov param1L, yRate
        mov param2,  yRate
        call #mult
        add t4, resultH wc
        addx t5, resultL

        mov param1H, resultH
        mov param1L, resultL
        call #sqrt

        mov t5, resultL

        'Calculate x rate
        mov param1L, xRate
        mov param2, xDist
        call #mult
        mov param1H, resultH
        mov param1L, resultL
        mov param2,  t5
        call #long_div

        mov param2, resultL    'Write the appropriate value
        call #calcLowTime
        mov t1, xAddr
        add t1, #2              'From Axis.spin LowWaitOffset
        wrlong resultL, t1

        'Calculate y rate
        mov param1L, yRate
        mov param2, yDist
        call #mult
        mov param1H, resultH
        mov param1L, resultL
        mov param2,  t5
        call #long_div

        mov param2, resultL    'Write the appropriate value
        call #calcLowTime
        mov t1, yAddr
        add t1, #2              'From Axis.spin LowWaitOffset
        wrlong resultL, t1

        'Calculate z rate
        mov param1L, zRate
        mov param2, zDist
        call #mult
        mov param1H, resultH
        mov param1L, resultL
        mov param2,  t5
        call #long_div

        mov param2, resultL    'Write the appropriate value
        call #calcLowTime
        mov t1, zAddr
        add t1, #2              'From Axis.spin LowWaitOffset
        wrlong resultL, t1                    
        
linearMovement_ret ret

rapidMovement
        mov param2, xRate
        call #calcLowTime
        mov t1, xAddr
        add t1, #2              'From Axis.spin LowWaitOffset
        wrlong resultL, t1

        mov param2, yRate
        call #calcLowTime
        mov t1, yAddr
        add t1, #2              'From Axis.spin LowWaitOffset
        wrlong resultL, t1

        mov param2, zRate
        call #calcLowTime
        mov t1, zAddr
        add t1, #2              'From Axis.spin LowWaitOffset
        wrlong resultL, t1                      
rapidMovement_ret ret

'Input: param2 contains the desired step rate
'Output: resultL contains the appropriate cycle delay
calcLowTime
        mov param1H, #0
        mov param1L, clockfreq
        call #long_div        
calcLowTime_ret ret        

        

{*cmd points to the beginning of the number
  t1 contains the final value
  parsing stops when a non-digit is encountered
}              
atoi
        mov t1, #0
:parse  rdbyte t2, cmd 
        cmp t2, #"0" wc         'Check if less than 0
        if_c jmp #atoi_ret
        cmp t2, #("9" + 1) wc   'Check if greater than 9
        if_nc jmp #atoi_ret
        add cmd, #1             'Advance ptr if we parsed it
        mov t3, t1
        shl t3, #3             't1 * 10
        add t1, t1
        add t1, t3
        sub t2, #"0"
        add t1, t2
        jmp #:parse
        
atoi_ret ret

'Perform a 64 bit x 32 bit --> 32 bit unsigned division
'Restoring divison algorithm from Hacker's Delight (http://www.hackersdelight.org/HDcode/divluh.c)
'Input: param1H:param1L    numerator   (dividend)
'       param2             denominator (divisor) 
'Output resultL            rounded quotient
'Destroys t1, t2, t3     
        
long_div
        mov t1, #0
        mov t2, #0
        mov t3, #32   
loop    mov t1, param1H
        shr t1, #31
        
        shl param1L, #1 wc    'shift (param1H:param1L) left one
        rcl param1H, #1
        
        mov t2, param1H       '(param1H|t) >= param2
        or t2, t1

        cmp param2, t2 wc, wz
if_c_or_z sub param1H, param2      'subtract if we can
if_c_or_z add param1L, #1     'set quotient bit

        djnz t3, #loop

        mov resultH, #0
        mov resultL, param1L

        'Round the result
        shr param2, #1       'Half of the divisor
        cmp param1H, param2 wc
if_nc_and_nz add resultL, #1    'Add if remainder is greater than quotient/2                
                                                  
long_div_ret ret

'32x32 bit multiply
'Multiplies mcandL by mplier 
'Gives a 64 bit result in resultH:L
'mcand  = param1L
'mplier = param2
'Destroys t1
mult
        mov resultH, #0
        mov resultL, #0
        mov param1H, #0

mul_loop cmp param2, #0 wz
mult_ret if_z ret

        shr param2, #1 wc
  if_nc jmp #shft

        add resultL, param1L wc
        addx resultH, param1H

shft    shl param1L, #1 wc
        rcl param1H, #1
        jmp #mul_loop

'Compute a rounded integer square root 64 bits -> 32 bits
'Input param1H:param1L
'Output rootL resultL
'Destroys t1, t2, tH:L

sqrt    mov t2, #32
        mov resultH, #0
        mov resultL, #0
        mov tH, #0
        mov tL, #0
        
sqrt_loop
        shl resultL, #1 wc        'root <<= 1
        rcl resultH, #1

        shl tL, #1 wc         'rem <<= 2
        rcl tH, #1
        shl tL, #1 wc
        rcl tH, #1

        mov t1, param1H              'a >> 62. We simply shift the high long 30 bits
        shr t1, #30

        add tL, t1 wc         '(rem << 2) + (a >> 62)
        addx tH, #0

        shl param1L, #1 wc         'a <<= 2
        rcl param1H, #1
        shl param1L, #1 wc
        rcl param1H, #1

        add resultL, #1 wc        'root++
        addx resultH, #0

        cmp resultL, tL wc,wz   'if (root <= rem)
        cmpx resultH, tH wc,wz

if_nc_and_nz jmp #els

        sub tL, resultL wc      'rem -= root
        subx tH, resultH

        add resultL, #1 wc        'root++
        add resultH, #0

        jmp #endif
                        
els     sub resultL, #1 wc        'root--
        subx resultH, #0

endif   djnz t2, #loop

        shr resultH, #1 wc
        rcr resultL, #1
                                          
sqrt_ret ret

clockfreq LONG 80_000_000

'Hub pointers
hubBuf res 1
statusAddr res 1                 
cmd res 1
xAddr res 1
yAddr res 1
zAddr res 1

status res 1
enablePin res 1
disablePin res 1

cmdChar res 1
t1 res 1
t2 res 1
t3 res 1
t4 res 1
t5 res 1
tH res 1
tL res 1
pathType res 1

'Parameters for the functions
'1 64 bit, 1 32 bit.  result = 64 bit
param1H res 1
param1L res 1
param2  res 1
resultH res 1
resultL res 1

'Movement variables
xRate res 1
yRate res 1
zRate res 1
xAccel res 1
yAccel res 1
zAccel res 1
xDist res 1
yDist res 1
zDist res 1

      FIT 496 