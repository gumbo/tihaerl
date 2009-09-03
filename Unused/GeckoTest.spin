CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000
VAR
  LONG i

PUB main
{{  dira[0]~~
  dira[1]~~
  dira[2]~~
  dira[3]~~

  outa[0] := 0
  outa[1] := 0
  outa[2] := 0  
  outa[3] := 0

'  moveY(4000, 20_000)
 ' moveX(7000, 20_000)


  
  repeat
    outa[3] := 0
'    moveX(10000, 10_000)
    moveY(10000, 10_000)

    outa[3] := 1
   'outa[3] := 1

      waitcnt(clkfreq / 2 + cnt)

'    moveX(10000, 10_000)
    moveY(10000, 10_000)

   waitcnt(clkfreq / 2 + cnt)}}


  '             mode  PLL     APIN
  ctra    := %00100_000 << 23 + 10  'Establish mode and APIN (BPIN is ignored)
  frqa    := $10_0000                     'Set FRQA so PHS[31] toggles every clock
  dira[10] := 1                              'Set APIN to output
  repeat                                    'infinite loop, so counter continues to run
   


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
    