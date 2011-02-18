CON
  _CLKMODE      = XTAL1 + PLL16x
  _XINFREQ      = 5_000_000

OBJ
  x : "Axis"
  Pins : "Pins"
  cp : "Synth"
  ser : "FullDuplexSerial"

VAR
  long go_flag

PUB main | i


  ser.start(31, 30, 0, 230400)

  go_flag := 0
  x.init(Pins#YStep, Pins#YDir, Pins#YLimit, Pins#Fault, @go_flag)
  x.setCurrentPosition(0)
  x.setAccelRate(100)
  x.setMaxVelocity(30000)

' dira[11] := 0

'  waitcnt(160_000_000 + cnt)

  ser.bin(INA[15..11], 5)
  ser.tx(13)

  cp.start("A", Pins#ChargePump, 15000)

  waitcnt(10_000_000 + cnt)

  ser.bin(INA[15..11], 5)
  ser.tx(13)

  repeat i from 0 to 3
    x.setRequestedPosition(40000)
    go_flag := TRUE
    repeat while x.isMoving
      if (INA[11] == 1)
        ser.tx("Y")
    x.setRequestedPosition(0)
    go_flag := TRUE
    repeat while x.isMoving
      if (INA[11] == 1)
        ser.tx("L")

  cp.stop("A")

  repeat

