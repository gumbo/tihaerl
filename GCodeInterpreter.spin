CON
  G_CODE = 0
  M_CODE = 1
  P_CODE = 2
  S_CODE = 3
  X_CODE = 4
  Y_CODE = 5
  Z_CODE = 6
  E_CODE = 7
  F_CODE = 8
  T_CODE = 9

  INCHES = 1
  MM     = 2
           
OBJ
  Constants : "Constants"
  Pins      : "Pins"
  'xAxis      : "VirtualAxis"
  'yAxis      : "VirtualAxis"
  'zAxis      : "VirtualAxis"
  'eAxis      : "VirtualAxis"
  xAxis      : "Axis"
  yAxis      : "Axis"
  zAxis      : "Axis"
  eAxis      : "Axis"
  'math      : "64bitMath"
  chargePump : "Synth"
  serial    : "SerialMirror"
  Errors    : "Errors"
  fp        : "F32"
  fmt       : "FloatString"
  settings  : "MachineSettings"
VAR
  'byte buf[200]
  
  long go_flag
  long clockFreq

  long ttmp

  byte updateLockID

  'Movement variables as the buffer sees them (in inches or mm)
  long xPos, yPos, zPos, ePos
  long feedRate

  ''TODO not needed?
  long xAccel, yAccel, zAccel, aAccel
  long xVel, yVel, zVel, aVel

  'GCode parsing variables
  long  cmdValues[10]

  word lastGCode

  long incremental_mode
  byte curUnits
PUB init

  'Initialize status
  go_flag := 0
  clockFreq := clkFreq

  fp.start

  updateLockID := LOCKNEW
   
  xAxis.init(Pins#XStep, Pins#XDir, Pins#XLimit, Pins#Fault, @go_flag)
  yAxis.init(Pins#YStep, Pins#YDir, Pins#YLimit, Pins#Fault, @go_flag)
  zAxis.init(Pins#ZStep, Pins#ZDir, Pins#ZLimit, Pins#Fault, @go_flag)
'  eAxis.init(Pins#EStep, Pins#EDir, Pins#XLimit, Pins#Fault, @go_flag)

  xPos := 0.0
  yPos := 0.0
  zPos := 0.0
  ePos := 0.0

  incremental_mode := FALSE

  setUnits(constants#MM)

  dira[31] := 0
  dira[30] := 1

PUB processCommand(bufPtr) | retStrPtr, start, middle, finish
  start := cnt

  if \parseGCodeCommand(bufPtr) <> 0
    return string("rs")

  middle := cnt

  retStrPtr := interpretGCodeCommand

  finish := cnt

  {
  serial.str(string("Parse: "))
  serial.dec((middle-start))
  serial.tx($0A)
  serial.tx($0D)

  serial.str(string("Inter: "))
  serial.dec((finish-middle))
  serial.tx($0A)
  serial.tx($0D)
  }

  return retStrPtr

PUB parseGCodeCommand(bufPtr)
{{ Call with a null terminated string. Determines the next action to perform and
  performs and calculations, then places it in the action queue.
  ABORTs on error
  }}

    '-1 is invalid for our integers, and represents -NaN for floats
    longfill(@cmdValues, -1, 9)

    repeat
      case byte[bufPtr]
          0: QUIT
        $0A: QUIT
        $0D: QUIT
        "G":
          cmdValues[G_CODE] := parseInt(@bufPtr)
        "M":
          cmdValues[M_CODE] := parseInt(@bufPtr)
        "T":
          cmdValues[T_CODE] := parseInt(@bufPtr)
        "S":
          cmdValues[S_CODE] := parseFloat(@bufPtr)
        "P":
          cmdValues[P_CODE] := parseFloat(@bufPtr)
        "X":
          cmdValues[X_CODE] := parseFloat(@bufPtr)
        "Y":
          cmdValues[Y_CODE] := parseFloat(@bufPtr)
        "Z":
          cmdValues[Z_CODE] := parseFloat(@bufPtr)
        "E":
          cmdValues[E_CODE] := parseFloat(@bufPtr)
        "F":
          cmdValues[F_CODE] := parseFloat(@bufPtr)
        " ":
          bufPtr++
        OTHER:
          ABORT Errors#INVALID_CHARACTER

  return 0

PRI interpretGCodeCommand | xDelta, yDelta, zDelta, eDelta
  if cmdValues[M_CODE] == 112
    emergency_stop

  if cmdValues[G_CODE] <> -1
    lastGCode := cmdValues[G_CODE]

    xDelta := xPos
    yDelta := yPos
    zDelta := zPos
    eDelta := ePos

    'Parse the updated position parameters (if any)
    if (incremental_mode == TRUE)
      if (cmdValues[X_CODE] <> -1)
        xPos := fp.FAdd(xPos, cmdValues[X_CODE])
      if (cmdValues[Y_CODE] <> -1)
        yPos := fp.FAdd(yPos, cmdValues[Y_CODE])
      if (cmdValues[Z_CODE] <> -1)
        zPos := fp.FAdd(zPos, cmdValues[Z_CODE])
      if (cmdValues[E_CODE] <> -1)
        ePos := fp.FAdd(ePos, cmdValues[E_CODE])
    else
      if (cmdValues[X_CODE] <> -1)
        xPos := cmdValues[X_CODE]
      if (cmdValues[Y_CODE] <> -1)
        yPos := cmdValues[Y_CODE]
      if (cmdValues[Z_CODE] <> -1)
        zPos := cmdValues[Z_CODE]
      if (cmdValues[E_CODE] <> -1)
        ePos := cmdValues[E_CODE]

    if (cmdValues[F_CODE] <> -1)
      feedRate := cmdValues[F_CODE]

    xDelta := fp.FAbs(fp.FSub(xPos, xDelta))
    yDelta := fp.FAbs(fp.FSub(yPos, yDelta))
    zDelta := fp.FAbs(fp.FSub(zPos, zDelta))
    eDelta := fp.FAbs(fp.FSub(ePos, eDelta))

    'Process G codes and enqueue moves
    case cmdValues[G_CODE]
      0:                   'Rapid move
        enqueueMovement(xDelta, yDelta, zDelta, eDelta, TRUE)
      1:                   'Linear interpolation
        enqueueMovement(xDelta, yDelta, zDelta, eDelta, FALSE)
      28:                  'Go home
        'TODO go home
        'set feed rate to lower value
        'go to some large negative position
        'disable limit pin monitoring
        'jog back slightly so the limits are off
        'restore the feed rate
      'Unbuffered commands
      4:                   'Dwell
        if (cmdValues[P_CODE] <> 01)
          waitcnt(80_000 * fp.FTrunc(cmdValues[P_CODE]) + cnt)
      20:                  'Units = inches
        setUnits(constants#INCHES)
      21:                  'Units = millimeters
        setUnits(constants#MM)
      90:                  'Absolute mode
        incremental_mode := FALSE
      91:                  'Relative mode
        incremental_mode := TRUE
      92:                  'Set position
        if (cmdValues[X_CODE] <> -1)
          xPos := cmdValues[X_CODE]
        if (cmdValues[Y_CODE] <> -1)
          yPos := cmdValues[Y_CODE]
        if (cmdValues[Z_CODE] <> -1)
          zPos := cmdValues[Z_CODE]
        if (cmdValues[E_CODE] <> -1)
          ePos := cmdValues[E_CODE]

  if cmdValues[M_CODE] <> -1
    case cmdValues[M_CODE]
      100:
        chargePump.start("A", Pins#ChargePump, 15000)
      101:
        chargePump.stop("A")
      114:
        bytemove(@xCoord, fmt.FloatToFormat(xPos, 8, 4), 8)
        bytemove(@yCoord, fmt.FloatToFormat(yPos, 8, 4), 8)
        bytemove(@zCoord, fmt.FloatToFormat(zPos, 8, 4), 8)
        bytemove(@eCoord, fmt.FloatToFormat(ePos, 8, 4), 8)
        return @coordStr
      115:
        return @versionStr

  return @okStr


PRI enqueueMovement(xDelta, yDelta, zDelta, eDelta, isRapid) | pathLength, accelSteps, feedRateSteps, accelOverPathLength, feedRateOverPathLength

  'Set the velocity for each move
  if (isRapid == TRUE)
    feedRateSteps := toSteps(settings.getRapidFeedRate)
    accelSteps := toSteps(settings.getAccel)
    xAxis.setAccelRate(accelSteps)
    yAxis.setAccelRate(accelSteps)
    zAxis.setAccelRate(accelSteps)
    eAxis.setAccelRate(accelSteps)
    xAxis.setMaxVelocity(feedRateSteps)
    yAxis.setMaxVelocity(feedRateSteps)
    zAxis.setMaxVelocity(feedRateSteps)
    eAxis.setMaxVelocity(feedRateSteps)
  else
    pathLength := fp.FSqr(fp.FAdd(fp.FAdd(fp.FMul(xDelta, xDelta), fp.FMul(yDelta, yDelta)), fp.FMul(zDelta, zDelta)))
    accelOverPathLength := fp.FDiv(settings.getAccel, pathLength)
    feedRateOverPathLength := fp.FDiv(feedRate, pathLength)

    xAxis.setAccelRate(toSteps(fp.FMul(xDelta, accelOverPathLength)))
    yAxis.setAccelRate(toSteps(fp.FMul(yDelta, accelOverPathLength)))
    zAxis.setAccelRate(toSteps(fp.FMul(zDelta, accelOverPathLength)))
    eAxis.setAccelRate(toSteps(fp.FMul(eDelta, accelOverPathLength)))
    xAxis.setMaxVelocity(toSteps(fp.FMul(xDelta, feedRateOverPathLength)))
    yAxis.setMaxVelocity(toSteps(fp.FMul(yDelta, feedRateOverPathLength)))
    zAxis.setMaxVelocity(toSteps(fp.FMul(zDelta, feedRateOverPathLength)))
    eAxis.setMaxVelocity(toSteps(fp.FMul(eDelta, feedRateOverPathLength)))

  serial.str(string("XPOS: "))
  serial.str(fmt.FloatToFormat(xPos, 8, 4))
  serial.str(string(" YPOS: "))
  serial.str(fmt.FloatToFormat(yPos, 8, 4))
  serial.str(string(" ZPOS: "))
  serial.str(fmt.FloatToFormat(zPos, 8, 4))
  serial.str(string(" EPOS: "))
  serial.str(fmt.FloatToFormat(ePos, 8, 4))

  xAxis.setRequestedPosition(toSteps(xPos))
  yAxis.setRequestedPosition(toSteps(yPos))
  zAxis.setRequestedPosition(toSteps(zPos))
  eAxis.setRequestedPosition(toSteps(ePos))

  go_flag := TRUE
  repeat while (xAxis.isMoving OR yAxis.isMoving OR zAxis.isMoving OR eAxis.isMoving) == TRUE

  serial.str(string(" DONE"))
  serial.CrLf

PRI toSteps(value)
  'TODO convert the position values
  if (curUnits == INCHES)
    'Inches to steps
    '5 tpi * 200 steps * 10 microsteps
    return fp.FRound(fp.FMul(value, 10000.0))
  else
    'mm to steps
    return fp.FRound(fp.FMul(value, 393.7007874))


PRI emergency_stop
  ''TODO disable charge pump

PRI setUnits(units)
  curUnits := units
  settings.setUnits(units)

PRI parseInt(strptrptr) : num | strptr, negative
{Parsing ends when the first non-numerical character is encountered
 Pointer points to the first invalid character
}
  strptr := long[strptrptr] + 1

  num := 0
  negative := FALSE
  repeat
    case byte[strptr]
      "+":
        ' ignore
      "-":
        negative := TRUE
      "0".."9":
        num := num * 10 + byte[strptr] - "0"
      other:
        quit
     ++strptr

  if (negative)
    num := -num

  long[strptrptr] := strptr

PRI parseFloat(strptrptr) : flt | strptr, significand, ssign, places, exp, esign
{{
  Converts string to floating-point number
  entry:
      strptr = pointer to z-string

  exit:
      flt = floating-point number


  Assumes the following floating-point syntax: [-] [0-9]* [ . [0-9]* ] [ e|E [-|+] [0-9]* ]
                                               ┌── ┌───── ┌─────────── ┌───────────────────
                                               │   │      │            │     ┌──── ┌─────
    Optional negative sign ────────────────────┘   │      │            │     │     │
    Digits ────────────────────────────────────────┘      │            │     │     │
    Optional decimal point followed by digits ────────────┘            │     │     │
    Optional exponent ─────────────────────────────────────────────────┘     │     │
      optional exponent sign ────────────────────────────────────────────────┘     │
      exponent digits ─────────────────────────────────────────────────────────────┘

  Examples of recognized floating-point numbers:
  "123", "-123", "123.456", "123.456e+09"
  Conversion stops as soon as an invalid character is encountered. No error-checking.

  Based on Ariba's StrToFloat in http://forums.parallax.com/forums/default.aspx?f=25&m=280607
  Expanded by Michael Park
}}
  strptr := long[strptrptr] + 1

  significand~
  ssign~
  exp~
  esign~
  places~
  repeat
    case byte[strptr]
      "-":
        ssign~~
      ".":
        places := 1
      "0".."9":
        significand := significand * 10 + byte[strptr] - "0"
        if places
          ++places                    'count decimal places
      "e", "E":
        ++strptr ' skip over the e or E
        repeat
          case byte[strptr]
            "+":
              ' ignore
            "-":
              esign~~
            "0".."9":
              exp := exp * 10 + byte[strptr] - "0"
            other:
              quit
          ++strptr
        quit
      other:
        quit
    ++strptr

  if ssign
    -significand
  flt := fp.FFloat(significand)

  ifnot esign  ' tenf table is in decreasing order, so the sign of exp is reversed
    -exp

  if places
    exp += places - 1

  flt := fp.FMul(flt, tenf[exp])              'adjust flt's decimal point

  long[strptrptr] := strptr

DAT
        long                1e+38, 1e+37, 1e+36, 1e+35, 1e+34, 1e+33, 1e+32, 1e+31
        long  1e+30, 1e+29, 1e+28, 1e+27, 1e+26, 1e+25, 1e+24, 1e+23, 1e+22, 1e+21
        long  1e+20, 1e+19, 1e+18, 1e+17, 1e+16, 1e+15, 1e+14, 1e+13, 1e+12, 1e+11
        long  1e+10, 1e+09, 1e+08, 1e+07, 1e+06, 1e+05, 1e+04, 1e+03, 1e+02, 1e+01
tenf    long  1e+00, 1e-01, 1e-02, 1e-03, 1e-04, 1e-05, 1e-06, 1e-07, 1e-08, 1e-09
        long  1e-10, 1e-11, 1e-12, 1e-13, 1e-14, 1e-15, 1e-16, 1e-17, 1e-18, 1e-19
        long  1e-20, 1e-21, 1e-22, 1e-23, 1e-24, 1e-25, 1e-26, 1e-27, 1e-28, 1e-29
        long  1e-30, 1e-31, 1e-32, 1e-33, 1e-34, 1e-35, 1e-36, 1e-37, 1e-38

teni    long  1, 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000

okStr    byte "ok",0
errStr   byte "!!",0

tempStr  byte "ok T:"
extTemp  byte "000.00 B:"
bedTemp  byte "000.00",0

coordStr byte "ok C: X:"
xCoord   byte "000.0000 Y:"
yCoord   byte "000.0000 Z:"
zCoord   byte "000.0000 E:"
eCoord   byte "000.0000",0

versionStr byte "ok PROTOCOL_VERSION:0.1 FIRMWARE_NAME:Propeller 5D MACHINE_TYPE:Custom EXTRUDER_COUNT:1",0

