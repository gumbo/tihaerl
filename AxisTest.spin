CON
  _CLKMODE      = XTAL1 + PLL16x
  _XINFREQ      = 5_000_000

OBJ
  x : "Axis"
  y : "Axis"
  f : "Synth"
'   vp    :       "Conduit"
' qs    :       "QuickSample"      'samples INA continuously
   
VAR
  long status
  long i
  long IOframe[400]
  
PUB main

{{
'Sample the INA port
 vp.register(qs.sampleINA(@IOframe,1))

'Share memory from varA..varC with ViewPort
 vp.share(@status,@status)
 }}

  f.Synth("A", 10, 15000)       'Charge pump


  status := 0
  x.init(0, 1, 8, @status, %100, %010, %001)
  y.init(2, 3, 9, @status, %100, %010, %001)

  x.setCurrentPosition(5000)
  x.setRequestedPosition(0)
  x.setAccelerationRate(500)
  x.setMaxStepRate(2000)

'  y.setCurrentPosition(10000)
'  y.setRequestedPosition(0)
 ' y.setAccelerationRate(500)
 ' y.setMaxStepRate(8000)

  status := %110

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