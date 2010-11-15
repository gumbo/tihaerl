CON
  _clkmode = xtal1 + pll16x                             ' use crystal x 16
  _xinfreq = 5_000_000

  RS_1 = 8
  RW_1 = 9
  E_1  = 10

  RS_2 = 11
  RW_2 = 12
  E_2  = 13


  D0 = 0
  D7 = 7

  DISPLAY_CLEAR = %0000_0001
  CURSOR_HOME = %0000_0010
  ENTRY_MODE  = %0000_0100
  CG_RAM_ADDR = %0100_0000
  DD_RAM_ADDR = %1000_0000
  

  BRIGHTNESS_100 = %0000_0000
  BRIGHTNESS_75  = %0000_0001
  BRIGHTNESS_50  = %0000_0010
  BRIGHTNESS_25  = %0000_0011
VAR
  LONG rs_pin, rw_pin, en_pin

PUB init(_rs_pin, _rw_pin, _en_pin)

  rs_pin := _rs_pin
  rw_pin := _rw_pin
  en_pin := _en_pin

  'resetDisplay

  
  {{
PUB main
  'waitcnt(clkfreq + cnt) 'Wait for initialization to complete

  OUTA[RS_1] := 0
  OUTA[E_1] := 0
  OUTA[RW_1] := 0
  OUTA[RS_2] := 0
  OUTA[E_2] := 0
  OUTA[RW_2] := 0
  OUTA[RESET] := 1
  DIRA[20]~~
  DIRA[0..7]~~
  DIRA[RESET]~~
  DIRA[E_1]~~
  DIRA[E_2]~~

  {{
  
  OUTA[RESET] := 0
  waitcnt(100_000 + cnt)
  OUTA[RESET] := 1

  

  
  'waitcnt(clkfreq + cnt)  

  write(RS_1, E_1, RW_1, 0, %0011_0000)    'Set bus width to 4 bits
  write(RS_1, E_1, RW_1, 0, %0011_0000)    'Set bus width to 4 bits
  write(RS_1, E_1, RW_1, 0, %0011_0000)    'Set bus width to 4 bits
'  write(RS_1, E_1, RW_1, 1, %0000_0011)    'Set brightness to 100%
'  read(RS_1, E_1, RW_1, 1)
  write(RS_1, E_1, RW_1, 0, %0000_1111)    'Display on, cursor blinking
'  read(RS_1, E_1, RW_1, 1)
'  write(RS_1, E_1, RW_1, 0, %0000_0001)    'Display clear

  write(RS_1, E_1, RW_1, 0, %0011_0000)    'Set bus width to 4 bits
  write(RS_1, E_1, RW_1, 1, %0000_0011)    'Set brightness to 100%

  waitcnt(500_000 + cnt)

 ' read(RS_1, E_1, RW_1, 1)
 ' write(RS_1, E_1, RW_1, 0, %0000_0110)    'Address increment, cursor shift
 ' read(RS_1, E_1, RW_1, 1)
 ' write(RS_1, E_1, RW_1, 0, %1000_0000)    'Set DD RAM Address

'  write(RS_1, E_1, RW_1, 0, %0001_0100)    'Move cursor one position right



'  write(RS_2, E_2, RW_2, 0, %0011_0000)    'Set bus width to 4 bits
 ' write(RS_2, E_2, RW_2, 0, %0011_0000)    'Set bus width to 4 bits
 ' write(RS_2, E_2, RW_2, 0, %0011_0000)    'Set bus width to 4 bits
 ' write(RS_2, E_2, RW_2, 1, %0000_0000)    'Set brightness to 100%
 ' write(RS_2, E_2, RW_2, 0, %0000_1111)    'Display on, cursor blinking
 ' write(RS_2, E_2, RW_2, 0, %0000_0001)    'Display clear
  

 ' waitcnt(500_000 + cnt)
 
  'write(RS_2, E_2, RW_2, 0, %0000_0110)    'Address increment, cursor shift
  'write(RS_2, E_2, RW_2, 0, %1000_0000)    'Set DD RAM Address
 
  'write(RS_2, E_2, RW_2, 0, %0001_0100)    'Move cursor one position right

'   OUTA[RS_1] := 1
  'write(RS_2, E_2, RW_2, 1, $41)    'Move cursor one position right
 ' read(RS_1, E_1, RW_1, 1)      
  write(RS_1, E_1, RW_1, 1, %0100_0001) 'A
  ' read(RS_1, E_1, RW_1, 1)
  'write(RS_1, E_1, RW_1, 0, %0001_0100)    'Move cursor one position right
'   write(RS_1, E_1, RW_1, 1, $6E) 'n

 ' OUTA[RS_1] := 0
  write(RS_1, E_1, RW_1, 1, $6E) 'n
  write(RS_1, E_1, RW_1, 1, $64) 'd
  write(RS_1, E_1, RW_1, 1, $79) 'y

 ' waitcnt(clkfreq + cnt)  

  'write(EN_2, 0, %0010_0000)
  'write(EN_2, 1, %0000_0000)
  'write(EN_2, 0, %0000_1111)
  'write(EN_2, 0, %0000_0001)


'------------------------------------------\

  write(RS_2, E_2, RW_2, 0, %0011_0000)    'Set bus width to 4 bits
  write(RS_2, E_2, RW_2, 0, %0011_0000)    'Set bus width to 4 bits
  write(RS_2, E_2, RW_2, 0, %0011_0000)    'Set bus width to 4 bits
  write(RS_2, E_2, RW_2, 0, %0000_1111)    'Display on, cursor blinking
  write(RS_2, E_2, RW_2, 0, %0011_0000)    'Set bus width to 4 bits
  write(RS_2, E_2, RW_2, 1, %0000_0000)    'Set brightness to 100%

  waitcnt(500_000 + cnt)

  write(RS_2, E_2, RW_2, 1, $49) 'I
  write(RS_2, E_2, RW_2, 1, $20) ' 
  write(RS_2, E_2, RW_2, 1, $6C) 'l
  write(RS_2, E_2, RW_2, 1, $6F) 'o
  write(RS_2, E_2, RW_2, 1, $76) 'v
  write(RS_2, E_2, RW_2, 1, $65) 'e

  write(RS_2, E_2, RW_2, 1, $20) ' 

  write(RS_2, E_2, RW_2, 1, $79) 'y
  write(RS_2, E_2, RW_2, 1, $6F) 'o
  write(RS_2, E_2, RW_2, 1, $75) 'u
'--------------------------------------------

'  waitcnt(clkfreq + cnt)

 ' DIRA[RS_2] := 0

  OUTA[20] := 1
  a := 0
  repeat
    a++
    }}    

PUB initDisplay(brightness)
  write(0, %0011_0000)    'Set bus width to 8 bits
  write(0, %0000_1110)    'Display on, cursor not blinking
  write(0, %0011_0000)    'Set bus width to 8 bits
  write(1, brightness)    'Set brightness

PUB writeCommand(command)
  write(0, command)

PUB writeData(val)
  write(1, val)

PUB writeString(strAddr)
    repeat strsize(strAddr)                             ' for each character in string
      writeData(byte[strAddr++])
      
PUB write(rs_state, data)
  if (rs_state == 0)
    DIRA[rs_pin] := 1           'Set the RS pin (0 == command, 1 == data)
  else
    DIRA[rs_pin] := 0

  DIRA[rw_pin] := 1             'Read == 1, Write == 0                                    

  OUTA[7..0] := data & $FF      'Data bytes

  DIRA[en_pin] := 0             'Latch the data
  DIRA[en_pin] := 1  
  DIRA[rw_pin] := 0             'Reset the R/W pin  
  DIRA[rs_pin] := 0             'Reset the RS pin

  waitcnt(100_000 + cnt)        'Wait minimum time before next write

PUB read
  DIRA[rs_pin] := 0
      
  DIRA[rw_pin] := 0
  DIRA[0..7] := $FF
  DIRA[0..7] := $00

  DIRA[en_pin] := 0             'Pin pulled up to 5V

  DIRA[en_pin] := 1
  DIRA[rs_pin] := 0             'Pin pulled up to 5V
 
