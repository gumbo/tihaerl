CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000
OBJ
  command : "SpinCommand"
  Serial  : "FullDuplexSerial"
  pins    : "Pins"    

VAR
  long i
  byte height[10]
PUB main | cmd, status

command.init

{
repeat
  command.readCommand
 }
 
   command.processCommand(string("RX100RY100."))
  command.processCommand(string("AX10AY10."))
  command.processCommand(string("AX-10AY-10."))      
  command.processCommand(string("PE."))
 
{     command.processCommand(string("M1Y100."))
     command.processCommand(string("M1X5000."))
     command.processCommand(string("M1Y200."))
     command.processCommand(string("M1X0000."))
     command.processCommand(string("M1Y300."))
     command.processCommand(string("M1X5000."))
     command.processCommand(string("M1Y400."))
     command.processCommand(string("M1X0000."))
     }
      ' repeat
        command.processCommand(string("M1X100."))
       ' command.processCommand(string("M1Y100."))
        'command.processCommand(string("M1Z100."))
        'command.processCommand(string("M1X0000."))
        'command.processCommand(string("M1Y0000."))
        'command.processCommand(string("M1Z0000."))
       
          
{     command.processCommand(string("M1Y100."))   
     command.processCommand(string("M1X0."))

     command.processCommand(string("M1Y200."))
     command.processCommand(string("M1X1000."))
     command.processCommand(string("M1Y300."))   
     command.processCommand(string("M1X0."))

     command.processCommand(string("M1Y400."))
     command.processCommand(string("M1X1000."))
     command.processCommand(string("M1Y500."))   
     command.processCommand(string("M1X0."))

     command.processCommand(string("M1Y600."))
     command.processCommand(string("M1X1000."))
     command.processCommand(string("M1Y700."))   
     command.processCommand(string("M1X0."))

     command.processCommand(string("M1Y800."))
     command.processCommand(string("M1X1000."))
          command.processCommand(string("M1Y900."))   
     command.processCommand(string("M1X0."))


   command.processCommand(string("M2X0Y0."))

 }

'    command.processCommand(string("M1X1Y1."))

 ' command.processCommand(string("H1."))
  '
command.processCommand(string("D."))

repeat      


DAT
buf        byte 0[200]          