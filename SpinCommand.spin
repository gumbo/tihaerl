CON
   BUF_END = "."  'End of the buffer marker (this set of commands)
   MODE    = "@"  'Mode specifier (axes, extruders, or query)

   EXTRUDER_MODE = "E"          'Extruder command mode
   AXES_MODE     = "A"          'Axes command mode
   QUERY_MODE    = "?"          'Query about current state

   { Axes Mode commands }
   
   '' R<axis><steps per second, 0-9999>
   STEP_RATE = "R" ' Maximum number of steps per second
   
   ''A<axis><steps per second^2>  Acceleration amount - this value is added to the axis step rate 50 times per second
   ''Negative acceleration specifies a deceleration rate
   ACCEL_RATE =  "A"
   
   ENABLE_DRIVES  = "E" 
   DISABLE_DRIVES = "D"

   HOME = "H"
   HOME_ORIGIN = "1"
   HOME_LIMIT  = "2"

   'Path mode definitions
   SMOOTH_CONTOURING  = "C"   ' Enable the use of splines for the next moves (calculated by the host)
   LINEAR      = "L"   ' Enable vector travel
   POSITIONING = "P"   ' Rapids
   
  {Path position definitions
    M<number of axes><axis><absolute position>...}
   MOVEMENT =  "M" ' Next position in set
   X_AXIS   =  "X"
   Y_AXIS   =  "Y"
   Z_AXIS   =  "Z"


   { Extruder Mode commands }

   TEMP = "T"   'New setpoint in degrees C

   { Query Mode commands }

   X_POS        = "X"
   Y_POS        = "Y"
   Z_POS        = "Z"

  'Offsets for the shared data array in RAM
  AXIS_LEN = 7  
  STATUSOFF = 0 * 4
  CMDPTR = 1 * 4
  X_DATA = 2 * 4    
  Y_DATA = (X_DATA + AXIS_LEN) * 4
  Z_DATA = (Y_DATA + AXIS_LEN) * 4

OBJ
  Constants : "Constants"
  Serial  : "FullDuplexSerial"
  Pins      : "Pins"
  xObj      : "Axis"
  yObj      : "Axis"
  zObj      : "Axis"
VAR
  byte buf[200]
  
  long status
  long cmdBufPtr

  long cmdOffset
  byte curMode
  byte pathType

  long clockFreq

  long ttmp

  'Movement variables
  long xPos, yPos, zPos
PUB init

   'Initialize status
   status := 0

   clockFreq := clkFreq
   
   xObj.init(Pins#XStep, Pins#XDir, @status, Constants#X_Go, Constants#X_Setup, Constants#X_Error)
   yObj.init(Pins#YStep, Pins#YDir, @status, Constants#Y_Go, Constants#Y_Setup, Constants#Y_Error)
   zObj.init(Pins#ZStep, Pins#ZDir, @status, Constants#Z_Go, Constants#Z_Setup, Constants#Z_Error)

  curMode := AXES_MODE

  dira[31] := 0
  dira[30] := 1
  
  Serial.start(31, 30, 0, 115200)
  
PUB readCommand | i
    i := 0
    repeat while buf[i-1] <> BUF_END AND i < 200
      buf[i] := Serial.rx
      i++      
    Serial.tx(".")
    if (processCommand(@buf) == 0)
      Serial.tx("#")
    else
      Serial.tx("!")
    i := 0

PUB processCommand(bufPtr)
{ Call with a BUF_END terminated string. Executes the command within
  TODO implement error reporting }

    cmdBufPtr := bufPtr
    cmdOffset := 0

    repeat while byte[cmdBufPtr][cmdOffset] <> BUF_END
      if(byte[cmdBufPtr][cmdOffset] == MODE)
         cmdOffset++
         curMode := byte[cmdBufPtr][cmdOffset]
         cmdOffset++
          
      if curMode == AXES_MODE
        case byte[cmdBufPtr][cmdOffset]
          STEP_RATE:
            processStepRate(@cmdOffset)
          ACCEL_RATE:
            processAccelRate(@cmdOffset)
          SMOOTH_CONTOURING:
            pathType := SMOOTH_CONTOURING
            cmdOffset++
          LINEAR:
            pathType := LINEAR
            cmdOffset++
          POSITIONING:
            pathType := POSITIONING
            cmdOffset++
          MOVEMENT:
            if (processMovement(@cmdOffset) == -1)
               return -1                                                         
          ENABLE_DRIVES:
'            dira |= Pins#Enable                         'Set as output low                               
 '           outa &= !Pins#Enable
            cmdOffset++
          DISABLE_DRIVES:
  '          dira &= !Pins#Enable                        'Set as input
            cmdOffset++
          HOME:
            processHome(@cmdOffset)                                  
          OTHER:
            return -1                      
      elseif  curMode == EXTRUDER_MODE
        case byte[cmdBufPtr][cmdOffset]
          TEMP:
            processExtruderTemp(@cmdOffset)
          OTHER:
            return -1
      elseif  curMode == QUERY_MODE
        case byte[cmdBufPtr][cmdOffset]
          X_POS:
            serial.dec(xObj.getCurrentPosition)
          Y_POS:
            serial.dec(yObj.getCurrentPosition)
          Z_POS:
            serial.dec(zObj.getCurrentPosition)
          OTHER:
            return -1                             

    return 0         
                
  
PRI processStepRate(indexPtr) | rate, axis, idxVal
  idxVal := long[indexPtr]
  idxVal++
  axis := byte[cmdBufPtr][idxVal]
  idxVal++
  long[indexPtr] := idxVal
  rate := atoi(indexPtr)

  rate := rate
  
  CASE axis
    X_AXIS:
      xObj.setMaxStepRate(rate)
    Y_AXIS:
      yObj.setMaxStepRate(rate)
    Z_AXIS:
      zObj.setMaxStepRate(rate)

PRI processAccelRate(indexPtr) | rate, axis, idxVal
  idxVal := long[indexPtr]
  idxVal++
  axis := byte[cmdBufPtr][idxVal]
  idxVal++  
  if (byte[cmdBufPtr][idxVal] == "-")
    idxVal++
    long[indexPtr] := idxVal
    rate := atoi(indexPtr)
    
    CASE axis
      X_AXIS:
        xObj.setDecelerationRate(rate)
      Y_AXIS:
        yObj.setDecelerationRate(rate)
      Z_AXIS:
        zObj.setDecelerationRate(rate)
  else
    long[indexPtr] := idxVal
    rate := atoi(indexPtr)
    
    CASE axis
      X_AXIS:
        xObj.setAccelerationRate(rate)
      Y_AXIS:
          yObj.setAccelerationRate(rate)
      Z_AXIS:
        zObj.setAccelerationRate(rate)
  
PRI processMovement(indexPtr) | idxVal, numAxes, pos, i, axis, xTime, yTime, zTime, xDist, yDist, zDist, pathLength
  idxVal := long[indexPtr]

  idxVal++
  numAxes := byte[cmdBufPtr][idxVal] - "0"

  idxVal++

  repeat i from 1 to numAxes    
    axis := byte[cmdBufPtr][idxVal]
    long[indexPtr] := ++idxVal
    pos := atoi(indexPtr)
    idxVal := long[indexPtr]
    CASE axis
      X_AXIS:
        xPos := pos
      Y_AXIS:
        yPos := pos
      Z_AXIS:                                                                     
        zPos := pos

  xDist := ||(xPos - xObj.getCurrentPosition)
  yDist := ||(yPos - yObj.getCurrentPosition)
  zDist := ||(zPos - zObj.getCurrentPosition)

  if (pathType == POSITIONING)
     xObj.configurePath(xPos, xDist, 0, 0)
     yObj.configurePath(yPos, 0, yDist, 0)
     zObj.configurePath(zPos, 0, 0, zDist)
  elseif (pathType == LINEAR)
     xObj.configurePath(xPos, xDist, yDist, zDist)
     yObj.configurePath(yPos, xDist, yDist, zDist)
     zObj.configurePath(zPos, xDist, yDist, zDist)      

  status |= Constants#X_Setup | Constants#Y_Setup | Constants#Z_Setup

  'Wait for all axes to finish processing their parameters
  repeat while status & (Constants#X_Setup | Constants#Y_Setup | Constants#Z_Setup) <> 0

  if (status & (Constants#X_Error | Constants#Y_Error | Constants#Z_Error)) <> 0
    return -1 
  
  status |= Constants#X_Go | Constants#Y_Go | Constants#Z_Go

  'Wait to return until all axes are done moving
  'WARNING May cause unintended effects if buffering is implemented
  repeat while status & (Constants#X_Go | Constants#Y_Go | Constants#Z_Go) <> 0

  return 0  
  
PRI processHome(idxPtr) | type, idxVal
  idxVal := long[idxPtr]
  idxVal++
  type := byte[cmdBufPtr][idxVal]

  Debug[10] := $ABABCDCD
  Debug[12] := type     
  Debug[14] := $CAFEBABE

  
  if type == HOME_ORIGIN
     Debug[13] := $1 
'     xObj.setMonitoredLimitPins(Pins#XHome)
 '    yObj.setMonitoredLimitPins(Pins#YHome)
'    zObj.home(Pins#ZHome)
  elseif type == HOME_LIMIT
    Debug[13] := $2
  '   xObj.setMonitoredLimitPins(Pins#XLim)
   '  yObj.setMonitoredLimitPins(Pins#YLim)

'  status := Constants#X_Go | Constants#Y_Go | Constants#Home

 ' repeat while status & (Constants#X_Go | Constants#Y_Go | Constants#Z_Go) <> 0
'    zObj.home(Pins#ZLim)  
  
PRI processExtruderTemp(indexPtr)  

PRI atoi (indexPtr) : num | idxVal, tmp
{Parsing ends when the first non-numerical character is encountered
 Pointer points to the first invalid character
}
  num := 0
  idxVal := word[indexPtr]
  repeat
    tmp := byte[cmdBufPtr][idxVal]
    if byte[cmdBufPtr][idxVal] => "0" AND byte[cmdBufPtr][idxVal] =< "9"
      num := num * 10 + (byte[cmdBufPtr][idxVal] - "0")
      idxVal++
    else
      word[indexPtr] := idxVal  'Store ptr value back      
      return

DAT
        Debug LONG $EFEFEFEF[50]      