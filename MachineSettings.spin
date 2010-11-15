OBJ
  constants : "Constants"
VAR
  byte curUnits
PUB setUnits(units)
  curUnits := units

{{
  Maximum axis acceleration in units/sec

  TODO this is in mm/msec - convert to mm/sec and
  then divide by 1000 in code
}}
PUB getAccel
  if (curUnits == constants#INCHES)
    return 0.1
  else
    return 2.54

{{
  Maximum axis velocity in units/sec
}}
PUB getRapidFeedRate
  if (curUnits == constants#INCHES)
    return 1.0
  else
    return 25.4

