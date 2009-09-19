CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000
VAR
  LONG i

PUB main

  '             mode  PLL     APIN
  ctra    := %00100_000 << 23 + 10  'Establish mode and APIN (BPIN is ignored)
  frqa    := $10_0000                     'Set FRQA so PHS[31] toggles every clock
  dira[10] := 1                              'Set APIN to output


  dira[0]~~
  dira[1]~~
  dira[2]~~
  dira[3]~~


  changeYDir(0)
  moveY(8000, 20_000)
'    changeXDir(0)
 ' moveX(20000, 20_000)

{{  changeXDir(1)
  changeYDir(1)

'  moveY(2000, 20_000)
 ' moveX(4000, 20_000)

  changeYDir(0)
  repeat i from 0 to 9
    changeXDir(1)
    moveX(5000, 20_000)
    moveY(500, 20_000)
    changeXDir(0)
    moveX(5000, 20_000)
    moveY(500, 20_000)
    }}

  'repeat

{{  changeXDir(0)
  changeYDir(0)  
  moveXY(3000, 20_000)
  changeXDir(1)
  changeYDir(0)
  moveXY(3000, 20_000)
  changeXDir(1)
  changeYDir(1)
  moveXY(3000, 20_000)
  changeXDir(0)
  changeYDir(1)
  moveXY(3000, 20_000)}}

  repeat
   

  
{{  repeat
    outa[3] := 0
'    moveX(10000, 10_000)
    moveY(10000, 10_000)

    outa[3] := 1
   'outa[3] := 1

      waitcnt(clkfreq / 2 + cnt)

'    moveX(10000, 10_000)
    moveY(10000, 10_000)

      waitcnt(clkfreq / 2 + cnt)
  }}


PUB moveX (steps, delay)
  repeat i from 0 to steps
    outa[0] := 1
    waitcnt(delay + cnt)
    outa[0] := 0
    waitcnt(delay + cnt)

PUB moveY (steps, delay)
  repeat i from 0 to steps
    outa[2] := 1
    waitcnt(delay + cnt)
    outa[2] := 0
    waitcnt(delay + cnt)

PUB moveXY (steps, delay)
  repeat i from 0 to steps
    outa[0] := 1
    outa[2] := 1
    waitcnt(delay + cnt)
    outa[0] := 0
    outa[2] := 0
    waitcnt(delay + cnt)

PUB changeXDir(direction)
  outa[1] := direction  
  waitcnt(100_000 + cnt)

PUB changeYDir(direction)
  outa[3] := direction
  waitcnt(100_000 + cnt)    