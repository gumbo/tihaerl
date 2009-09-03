CON
  XStep  = 1 << 0
  XDir   = 1 << 1
  YStep  = 1 << 2
  YDir   = 1 << 3
  ZStep  = 1 << 4
  ZDir   = 1 << 5
  AStep  = 1 << 6
  ADir   = 1 << 7
  
  XLimit  = 1 << 12
  YLimit  = 1 << 13
  ZLimit  = 1 << 14
  ALimit  = 1 << 15

  VFD_PWM = 1 << 16
  FAULT   = 1 << 11
  CHARGE_PUMP = 1 << 10

  OUTPUT_1 = 1 << 8
  OUTPUT_2 = 1 << 9

'Ethernet

  ETH_CS  = 1 << 21
  ETH_SCK = 1 << 20
  ETH_SI  = 1 << 19
  ETH_SO  = 1 << 18
  ETH_INT = 1 << 17
                   
  'SPI
'  CLK    = 1 << 6
 ' DIN    = 1 << 8
'  DOUT   = 1 << 9

 ' CS1    = 1 << 24
 ' CS2    = 1 << 25
 ' CS3    = 1 << 26
 ' CS4    = 1 << 27

  RX     = 1 << 31
  TX     = 1 << 30
PUB init 