CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000
OBJ
  command : "SpinCommand"
'  Serial  : "FullDuplexSerial"
  pins    : "Pins"
  f       : "Synth"

PUB main | cmd, status

command.init

  f.Synth("A", 10, 15000)       'Charge pump


  repeat
    command.readCommand
              