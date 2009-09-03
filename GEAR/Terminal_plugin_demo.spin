'' Terminal_plugin_demo.spin
''
'' description:
''   demonstrates the functionality of the Terminal.xml plugin for the Gear emulator.



CON

  _clkmode = xtal1 + pll16x                             ' use crystal x 16
  _xinfreq = 5_000_000                                  ' 5 MHz cyrstal (sys clock = 80 MHz)

  RX_PIN   = 0
  TX_PIN   = 1
  MODE     = %0011
  BAUD     = 160_000

  ESC = $1B



VAR
  byte rcvStr[100], i, CRLFflags



OBJ

  serial : "FullDuplexSerial"



PUB main | rxByte

  serial.start(RX_PIN, TX_PIN, MODE, BAUD)

  help

  repeat
    case (rxByte := serial.rx)
      $d       :
        CRLFflags |= %01
      $a       :
        CRLFflags |= %10
      $0..$7F :
        CRLFflags := %00
        rcvStr[i++] := rxByte

    serial.tx(rxByte)
    if strComp(@rcvStr,string("demo"))
      demo
    if strComp(@rcvStr,string("help"))
      help      
    if CRLFflags == %11
      prompt


PRI help
  serial.str(@cls)
  serial.str(@help_txt)
  prompt


PRI demo
  serial.str(@cls)
  serial.str(@rowCol_txt)
  waitcnt(clkfreq/500+cnt)
  serial.str(string(ESC,"[",15,";",39,"H"))
  serial.str(string("x---Row 15, Col 39"))
  waitcnt(clkfreq/500+cnt)
  repeat 18
    serial.str(@backspace)
  serial.str(string(ESC,"[",31,";",80,"H"))
  serial.str(@CRLF)  
  serial.str(@text_txt)
  serial.str(@CRLF)  

  waitcnt(clkfreq/250+cnt)
  serial.str(string(ESC,"[",15,";",39,"H"))
  serial.str(@clrLnCR)
  serial.str(string(ESC,"[",15,";",43,"H"))
  serial.str(string("<<Clear Line from cursor right.>>"))
  serial.str(string(ESC,"[",15,";",39,"H"))
  waitcnt(clkfreq/500+cnt)
  serial.str(@clrLnCL)
  serial.str(string(ESC,"[",15,";",3,"H"))
  serial.str(string("<<Clear Line from cursor left.>>"))
  waitcnt(clkfreq/250+cnt)
  serial.str(string(ESC,"[",15,";",39,"H"))
  serial.str(@clrLn)
  serial.str(string(ESC,"[",15,";",29,"H"))
  serial.str(string("<<Clear entire Line.>>"))
  
  waitcnt(clkfreq/250+cnt)
  serial.str(string(ESC,"[",15,";",39,"H"))
  serial.str(@clsCD)
  serial.str(string(ESC,"[",22,";",23,"H"))
  serial.str(string("<<Clear Screen from cursor down.>>"))
  serial.str(string(ESC,"[",15,";",39,"H"))
  waitcnt(clkfreq/500+cnt)
  serial.str(@clsCU)
  serial.str(string(ESC,"[",8,";",23,"H"))
  serial.str(string("<<Clear Screen from cursor up.>>"))
  waitcnt(clkfreq/250+cnt)
  serial.str(@cls)
  prompt


PRI prompt
  CRLFflags := %00
  serial.tx(">")
  bytefill(@rcvStr,0,100)
  i~
  serial.rxflush



DAT

backspace     byte  $8,0
CRLF          byte  $d,$a,0
home          byte  ESC,"[H",0        'cursor home
clsCD         byte  ESC,"[0J",0       'clear screen from cursor down
clsCU         byte  ESC,"[1J",0       'clear screen from cursor up 
cls           byte  ESC,"[2J",0       'clear entire screen
clrLnCR       byte  ESC,"[0K",0       'clear line from cursor right
clrLnCL       byte  ESC,"[1K",0       'clear line from cursor left
clrLn         byte  ESC,"[2K",0       'clear entire line

help_txt      byte $9,$9,$9,$9,"*** DEMO - Terminal.xml Plugin ***",$d,$a,$d,$a
              byte "Receives and Transmits 8 bit, 1 stop, no parity.",$d,$a
              byte "Maximum BAUD rates for Transmit and Receive are:",$d,$a
              byte $9,"115200 standard",$d,$a
              byte $9,"160000 non-standard",$d,$a
              byte $9,"(Tested Recieve up to 230400 BAUD / Transmit fails at 230400 BAUD)",$d,$a,$d,$a
              byte "The Terminal screen Word Wraps text and accepts the following control codes:",$d,$a
              byte $9,"$08",$9,$9,$9,$9,$9,$9,$9,"= backspace",$d,$a
              byte $9,"$09",$9,$9,$9,$9,$9,$9,$9,"= tab",$d,$a
              byte $9,"$0D",$9,$9,$9,$9,$9,$9,$9,"= carriage return",$d,$a
              byte $9,"$0A",$9,$9,$9,$9,$9,$9,$9,"= line feed",$d,$a
              byte $9,"$1B + '[H'",$9,$9,$9,$9,$9,"= home",$d,$a
              byte $9,"$1B + '[' + row + ';' + col + 'H'",$9,"= place cursor at row and column",$d,$a
              byte $9,"$1B + '[0J'",$9,$9,$9,$9,$9,"= clear screen from cursor down",$d,$a
              byte $9,"$1B + '[1J'",$9,$9,$9,$9,$9,"= clear screen from cursor up",$d,$a
              byte $9,"$1B + '[2J'",$9,$9,$9,$9,$9,"= clear screen",$d,$a
              byte $9,"$1B + '[0K'",$9,$9,$9,$9,$9,"= clear line from cursor right",$d,$a
              byte $9,"$1B + '[1K'",$9,$9,$9,$9,$9,"= clear line from cursor left",$d,$a
              byte $9,"$1B + '[2K'",$9,$9,$9,$9,$9,"= clear entire line",$d,$a,$d,$a
              byte "To send a hex value, to your application, use the '$' prefix.",$d,$a
              byte "For example $0d$0a will send CRLF.",$d,$a
              byte "To send a '$' use '$$'.",$d,$a,$d,$a
              byte "Type something, in the TextBox above, and press SEND to see it echo'd on the Terminal.",$d,$a ,$d,$a
              byte "At the Terminal prompt '>', in the TextBox type 'help' to display this screen or 'demo' to run the demo and press SEND.",$d,$a,0

rowCol_txt    file "rowCol.txt"
              byte 0
text_txt      file "lincoln.txt"
              byte 0
          