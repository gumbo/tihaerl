CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000

 X_AXIS = 0
 Y_AXIS = 1
 Z_AXIS = 2
 E_AXIS = 3

 RESET = 14

 UNITS  = "U"
 LAYER  = "L"
 EXTRUDER = "T"
 BED    = "B"
 STATUS = "S"

 INCHES = 0
 MM     = 1

OBJ
  leftDisplay  : "Noritake VFD"
  rightDisplay : "Noritake VFD"
  serial       : "FullDuplexSerial"
  pins         : "Pins"
  fmt          : "FloatString"
  fp           : "F32"

VAR
  byte curUnits

PUB main | i
  resetDisplays
  leftDisplay.init(0, leftDisplay#BRIGHTNESS_75)
  rightDisplay.init(1, rightDisplay#BRIGHTNESS_75)

  fp.start

  curUnits := mm

  initFormat

  repeat i from 0 to 3
    updateAxis(i, fp.FFloat(i+2))

  i := 67498

  repeat
     updateAxis(2, fp.FFloat(i))

PRI initFormat | i
  leftDisplay.selectCharacter(0, 0)
  leftDisplay.str(string("Layer      ____/____"))
  leftDisplay.selectCharacter(1, 0)
  leftDisplay.str(string("Extruder Temp      C"))
  leftDisplay.selectCharacter(1, 18)
  leftDisplay.writeData($DF)
  leftDisplay.selectCharacter(2, 0)
  leftDisplay.str(string("Build Sf Temp      C"))
  leftDisplay.selectCharacter(2, 18)
  leftDisplay.writeData($DF)

  leftDisplay.selectCharacter(3, 0)
  leftDisplay.str(string("Status: "))


  rightDisplay.selectCharacter(0, 0)
  rightDisplay.str(string("X:"))
  rightDisplay.selectCharacter(1, 0)
  rightDisplay.str(string("Y:"))
  rightDisplay.selectCharacter(2, 0)
  rightDisplay.str(string("Z:"))
  rightDisplay.selectCharacter(3, 0)
  rightDisplay.str(string("E:"))

  updateUnits

PRI updateUnits | line
  repeat line from 0 to 3
    rightDisplay.selectCharacter(line, 11)

    if (curUnits == INCHES)
      rightDisplay.str(string("in"))
    else
      rightDisplay.str(string("mm"))

PRI updateAxis(axis, value)
  'TODO doesn't work for mm - need hundreds
  rightDisplay.selectCharacter(axis, 2)
  rightDisplay.str(fmt.FloatToFormat(fromSteps(value), 10, 4))

PRI fromSteps(value)
  'TODO convert the position values
  if (curUnits == INCHES)
    'Steps to inches
    '5 tpi * 200 steps * 10 microsteps
    return fp.FDiv(value, 10000.0)
  else
    'steps to mm
    return fp.FDiv(value, 393.7007874)

PRI resetDisplays
  OUTA[RESET] := 0
  waitcnt(100_000 + cnt)
  OUTA[RESET] := 1
  waitcnt(500_000 + cnt)

