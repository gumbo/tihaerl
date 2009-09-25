CON
  XStep  = 0
  XDir   = 1
  YStep  = 2
  YDir   = 3
  ZStep  = 4
  ZDir   = 5
  AStep  = 6
  ADir   = 7
  
  XLimit  = 12
  YLimit  = 13
  ZLimit  = 14
  ALimit  = 15

  VFD_PWM = 1 << 16
  FAULT   = 1 << 11
  CHARGE_PUMP = 1 << 10

  OUTPUT_1 = 1 << 8
  OUTPUT_2 = 1 << 9

'Ethernet

  ETH_CS  = 21
  ETH_SCK = 20
  ETH_SI  = 19
  ETH_SO  = 18
  ETH_INT = 17
                   
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