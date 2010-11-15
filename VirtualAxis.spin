CON
  AccelOffset      = 0
  MaxRateOffset    = 1
  CurPosOffset     = 2
  ReqPosOffset     = 3

VAR
  long moving_flag              'TRUE if we haven't finished moving
  long axisData[4]
OBJ
  serial : "SerialMirror"
PUB init(stepPinNum, dirPinNum, limitPinNum, faultPinNum, goflagAddr)

    longfill(@axisData, $0, 4)

    moving_flag   := FALSE

PUB isMoving
    return moving_flag
PUB setRequestedPosition(reqPosition)
  axisData[ReqPosOffset] := reqPosition
  serial.dec(reqPosition)
  serial.tx(" ")
PUB getRequestedPosition
  return axisData[ReqPosOffset]
PUB setCurrentPosition(curPosition)
  axisData[CurPosOffset] := curPosition
PUB getCurrentPosition
  return axisData[CurPosOffset]
PUB setAccelRate(_accelRate)
  {{
    Set the maximum acceleration of this axis in steps/sec
  }}

  serial.dec(_accelRate)
  serial.tx(" ")
PUB setMaxVelocity(maxRate)
  {{
    Set the maximum velocity of this axis in steps/sec
  }}

  serial.dec(maxRate)
  serial.tx(" ")


