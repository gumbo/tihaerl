CON
  _clkmode = xtal1 + pll16x                             ' use crystal x 16
  _xinfreq = 5_000_000

  RS_1 = 8
  RW_1 = 9
  EN_1  = 10

  RS_2 = 11
  RW_2 = 12
  EN_2  = 13

  RESET = 14

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

PUB init(display_num, brightness)

  if (display_num == 0)
    rs_pin := RS_1
    rw_pin := RW_1
    en_pin := EN_1
  else
    rs_pin := RS_2
    rw_pin := RW_2
    en_pin := EN_2

  OUTA[rs_pin] := 0
  OUTA[en_pin] := 0
  OUTA[rw_pin] := 0
  OUTA[RESET] := 1
  DIRA[0..7]~~
  DIRA[RESET]~~
  DIRA[en_pin]~~

'  resetDisplay

  initDisplay(brightness)


PRI initDisplay(brightness)
  write(0, %0011_0000)    'Set bus width to 8 bits
  write(0, %0000_1110)    'Display on, cursor not blinking
  write(0, %0011_0000)    'Set bus width to 8 bits
  write(1, brightness)    'Set brightness
  write(0, DISPLAY_CLEAR)

PUB selectLine(line) | addr
  case line
    0: addr := $00
    1: addr := $40
    2: addr := $14
    3: addr := $54

  writeCommand(DD_RAM_ADDR | addr)

PUB selectCharacter(line, cursor) | addr
  case line
    0: addr := $00
    1: addr := $40
    2: addr := $14
    3: addr := $54

  addr += cursor

  writeCommand(DD_RAM_ADDR | addr)

PUB str(strAddr)
    repeat strsize(strAddr) 'while byte[strAddr] <> 0
      writeData(byte[strAddr++])
PUB dec(value) | i

'' Print a decimal number

  if value < 0
    -value
    writeData("-")

  i := 1_000_000_000

  repeat 10
    if value => i
      writeData(value / i + "0")
      value //= i
      result~~
    elseif result or i == 1
      writeData("0")
    i /= 10


PUB hex(value, digits)

'' Print a hexadecimal number

  value <<= (8 - digits) << 2
  repeat digits
    writeData(lookupz((value <-= 4) & $F : "0".."9", "A".."F"))


PUB bin(value, digits)

'' Print a binary number

  value <<= 32 - digits
  repeat digits
    writeData((value <-= 1) & 1 + "0")

PRI writeCommand(command)
  write(0, command)

PUB writeData(val)
  write(1, val)

PRI write(rs_state, data)
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

PRI read
  DIRA[rs_pin] := 0
      
  DIRA[rw_pin] := 0
  DIRA[0..7] := $FF
  DIRA[0..7] := $00

  DIRA[en_pin] := 0             'Pin pulled up to 5V

  DIRA[en_pin] := 1
  DIRA[rs_pin] := 0             'Pin pulled up to 5V

PUB resetDisplays
  OUTA[RESET] := 0
  waitcnt(100_000 + cnt)
  OUTA[RESET] := 1
  waitcnt(500_000 + cnt)
