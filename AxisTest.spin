CON
  _CLKMODE      = XTAL1 + PLL16x
  _XINFREQ      = 5_000_000

OBJ
  x : "Axis"
  y : "Axis"  
  f : "Synth"
  Constants : "Constants"
'   vp    :       "Conduit"
' qs    :       "QuickSample"      'samples INA continuously
  Serial: "FullDuplexSerial"
   
VAR
  long status
  long i
  
PUB main

{{
'Sample the INA port
 vp.register(qs.sampleINA(@IOframe,1))

'Share memory from varA..varC with ViewPort
 vp.share(@status,@status)
 }}
   Serial.start(31, 30, 0, 115200)

  f.Synth("A", 10, 15000)       'Charge pump


  status := 0
  x.init(0, 1, 8, @status, Constants#X_Go, Constants#X_Setup, Constants#X_Error)
  y.init(2, 3, 9, @status, Constants#Y_Go, Constants#Y_Setup, Constants#Y_Error)     

  x.setCurrentPosition(0)
  y.setCurrentPosition(0)
  
  x.setAccelerationRate(500)
  x.setMaxStepRate(10000)
  y.setAccelerationRate(500)
  y.setMaxStepRate(10000)

  repeat
    Serial.str(string("X0"))
    Serial.dec(x.getCurrentPosition)
    Serial.tx($0A0D)
    x.setRequestedPosition(1000)
    status := Constants#X_Setup
    repeat while status & Constants#X_Setup <> 0
    status := Constants#X_Go
    repeat while status & Constants#X_Go <> 0

    Serial.str(string("Y0"))
    Serial.dec(y.getCurrentPosition)
    Serial.tx($0A0D)     
    y.setRequestedPosition(1000)
    status := Constants#Y_Setup
    repeat while status & Constants#Y_Setup <> 0
    status := Constants#Y_Go
    repeat while status & Constants#Y_Go <> 0

    Serial.str(string("X1"))
    Serial.dec(x.getCurrentPosition)    
    Serial.tx($0A0D)
    Serial.str(string("Y1"))
    Serial.dec(y.getCurrentPosition)    
    Serial.tx($0A0D)    
    x.setRequestedPosition(0)
    y.setRequestedPosition(0)
    status := Constants#X_Setup | Constants#Y_Setup
    repeat while status & (Constants#X_Setup | Constants#Y_Setup) <> 0
    status := Constants#X_Go | Constants#Y_Go
    repeat while status & (Constants#X_Go | Constants#Y_Go) <> 0
     
     
  repeat

{{
  dira[2]~~
  dira[3]~~

  outa[3] := 0

  repeat
    outa[3] := NOT outa[3]
    waitcnt(300_000 + cnt)
     
     
    f.Synth("B", 10, 15000)
     
     
    repeat i from 500 to 16000 step 500
      f.Synth("A", 2, i)
      waitcnt(80_000 + cnt)
     
    waitcnt(20_000_000 + cnt)
     
    repeat i from 16000 to 0 step 500
      f.Synth("A", 2, i)
      waitcnt(80_000 + cnt)


  }}  

  repeat     