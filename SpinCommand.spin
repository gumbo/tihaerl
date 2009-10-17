CON
   BUF_END = "."  'End of the buffer marker (this set of commands)
   MODE    = "@"  'Mode specifier (axes, extruders, or query)

   EXTRUDER_MODE = "E"          'Extruder command mode
   AXES_MODE     = "A"          'Axes command mode
   QUERY_MODE    = "?"          'Query about current state

   { Axes Mode commands }
   
   '' R<axis><steps per second, 0-9999>
   STEP_RATE = "R" ' Maximum number of steps per second
   
   ''A<axis><steps per second^2>  Acceleration amount - this value is added to or subtracted from
   ''the axis step rate 1000 times per second
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
   A_AXIS   =  "A"    


   { Extruder Mode commands }

   TEMP = "T"   'New setpoint in degrees C

   { Query Mode commands }

   X_POS        = "X"
   Y_POS        = "Y"
   Z_POS        = "Z"
   A_POS        = "A"  

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

  byte updateLockID

  'Movement variables
  long xPos, yPos, zPos, aPos
PUB init

   'Initialize status
   status := 0   
   clockFreq := clkFreq

   updateLockID := LOCKNEW
   
   xObj.init(Pins#XStep, Pins#XDir, Pins#XLimit, @status, Constants#X_Go, Constants#X_Setup, Constants#X_Error, updateLockID)
   yObj.init(Pins#YStep, Pins#YDir, Pins#YLimit, @status, Constants#Y_Go, Constants#Y_Setup, Constants#Y_Error, updateLockID)
   zObj.init(Pins#ZStep, Pins#ZDir, Pins#ZLimit, @status, Constants#Z_Go, Constants#Z_Setup, Constants#Z_Error, updateLockID)

  curMode := AXES_MODE
  pathType := POSITIONING

  xPos := 0
  yPos := 0
  zPos := 0
  aPos := 0

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
      Serial.str(string("OK"))
    else
      Serial.str(string("ERR"))
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
          
      elseif curMode == AXES_MODE
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
           cmdOffset++
          Y_POS:
            serial.dec(yObj.getCurrentPosition)
            cmdOffset++
          Z_POS:
            serial.dec(zObj.getCurrentPosition)
            cmdOffset++            
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

'  Serial.str(string("Vel"))
'  Serial.tx(axis)
'  Serial.dec(rate)

  
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
  long[indexPtr] := idxVal
  rate := atoi(indexPtr)

 ' Serial.str(string("Accel"))
 ' Serial.tx(axis)
 ' Serial.dec(rate)

    
  CASE axis
    X_AXIS:
      xObj.setAccelerationRate(rate)
    Y_AXIS:
      yObj.setAccelerationRate(rate)
    Z_AXIS:
      zObj.setAccelerationRate(rate)
  
PRI processMovement(indexPtr) | idxVal, numAxes, pos, i, axis, relative, setupMask, goMask 
  idxVal := long[indexPtr]

  idxVal++
  numAxes := byte[cmdBufPtr][idxVal] - "0"

  idxVal++

  ''
  ''
  '' TODO redo this
  '' allow for relative and absolute movements
  '' TODO  
  ''  
  ''

  setupMask := 0
  goMask := 0

  repeat i from 1 to numAxes
'    Serial.dec(i)    
    axis := byte[cmdBufPtr][idxVal]
    if (byte[cmdBufPtr][idxVal + 1] == "-" OR byte[cmdBufPtr][idxVal + 1] == "+")
      relative := 1
    long[indexPtr] := ++idxVal
    pos := atoi(indexPtr)
    idxVal := long[indexPtr]
    CASE axis
      X_AXIS:
        setupMask |= Constants#X_Setup
        goMask    |= Constants#X_Go
        if (relative == 1)
          xPos := xObj.getCurrentPosition + pos
        else
          xPos := pos
      Y_AXIS:
        setupMask |= Constants#Y_Setup
        goMask    |= Constants#Y_Go
        if (relative == 1)
          yPos := yObj.getCurrentPosition + pos
        else
          yPos := pos
      Z_AXIS:
        setupMask |= Constants#Z_Setup
        goMask    |= Constants#Z_Go                                               
        if (relative == 1)
          zPos := zObj.getCurrentPosition + pos
        else
          zPos := pos

  
  if (pathType == POSITIONING)
    xObj.setRequestedPosition(xPos)
    yObj.setRequestedPosition(yPos)
    zObj.setRequestedPosition(zPos)
  elseif (pathType == LINEAR)
    pathType := LINEAR          'TODO nop


 ' Serial.tx("X")  
 ' Serial.dec(xObj.getCurrentPosition)
 ' Serial.tx("|")
 ' Serial.dec(xObj.getRequestedPosition)  
 ' Serial.tx("Y")
 ' Serial.dec(yObj.getCurrentPosition)
 ' Serial.tx("|")
 ' Serial.dec(yObj.getRequestedPosition)    

  status := setupMask

  'Wait for all axes to finish processing their parameters
  repeat while (status & setupMask) <> 0

  'Serial.tx("A")

  if (status & (Constants#X_Error | Constants#Y_Error | Constants#Z_Error)) <> 0
    return -1

  status := goMask

  'Serial.tx("B")

  'Wait to return until all axes are done moving
  'WARNING May cause unintended effects if buffering is implemented
  repeat while (status & goMask) <> 0

  'Serial.tx("X")  
  'Serial.dec(xObj.getCurrentPosition)
  'Serial.tx("Y")
  'Serial.dec(yObj.getCurrentPosition)    


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

PRI atoi (indexPtr) : num | idxVal, negative
{Parsing ends when the first non-numerical character is encountered
 Pointer points to the first invalid character
}
  num := 0
  negative := 0
  idxVal := word[indexPtr]
  repeat
    if byte[cmdBufPtr][idxVal] == "-"
      negative := 1
      idxVal++
    if byte[cmdBufPtr][idxVal] == "+"
      idxVal++  
    if byte[cmdBufPtr][idxVal] => "0" AND byte[cmdBufPtr][idxVal] =< "9"
      num := num * 10 + (byte[cmdBufPtr][idxVal] - "0")
      idxVal++
    else
      word[indexPtr] := idxVal  'Store ptr value back
      if (negative)
        num := -num    
      return

DAT
        Debug LONG $EFEFEFEF[50]      