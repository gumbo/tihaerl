CON
  RS_1 = 8
  RW_1 = 9
  E_1  = 10

  RS_2 = 11
  RW_2 = 12
  E_2  = 13

OBJ
  vfd1: "Noritake VFD"
  vfd2: "Noritake VFD"

PUB main

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
  
  vfd1.init(RS_1, RW_1, E_1)
  vfd2.init(RS_2, RW_2, E_2)

  vfd1.initDisplay($01)
  vfd2.initDisplay($02)

  vfd1.writeString(STRING("this is cool"))
    vfd2.writeString(STRING("Peter"))  