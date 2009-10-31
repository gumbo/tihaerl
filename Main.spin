CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000
OBJ
  command : "SpinCommand"
'  Serial  : "FullDuplexSerial"
  pins    : "Pins"

PUB main | cmd, status

  command.init
                                 
  repeat
    command.readCommand
    
              