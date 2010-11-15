CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000

CON
  RESET = 14

  RS_1 = 8
  RW_1 = 9
  E_1  = 10

  RS_2 = 11
  RW_2 = 12
  E_2  = 13

OBJ
  ser : "FullDuplexSerial"
  vfd1: "Noritake VFD"
  vfd2: "Noritake VFD"

PUB main | chr

'  ser.start(16, 15, 0, 115200)
   ser.start(31, 30, 0, 115200)

  {
  OUTA[RS_1] := 0
  OUTA[E_1] := 0
  OUTA[RW_1] := 0
  OUTA[RS_2] := 0
  OUTA[E_2] := 0
  OUTA[RW_2] := 0
  OUTA[14] := 1
  DIRA[20]~~
  DIRA[0..7]~~
  DIRA[14]~~
  DIRA[E_1]~~
  DIRA[E_2]~~
  }
  
  vfd1.init(RS_1, RW_1, E_1)
  vfd2.init(RS_2, RW_2, E_2)

  resetDisplay

  vfd1.initDisplay($01)
  vfd2.initDisplay($02)

  vfd1.writeString(STRING("this is cool"))
  vfd2.writeString(STRING("Peter"))

  repeat

PUB resetDisplay
  OUTA[RESET] := 0
  waitcnt(100_000 + cnt)
  OUTA[RESET] := 1
  waitcnt(500_000 + cnt)

