CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000

  MIN_VAL = $007
  MAX_VAL = $FFB

OBJ
  vfd : "Noritake VFD"
  adc : "ADC_INPUT_DRIVER"
  fp  : "F32"
  fmt : "FloatString"

PUB main | val,i
  vfd.resetDisplays
  vfd.init(0, vfd#BRIGHTNESS_100)
  adc.start(26, 25, 24, 27, 4, 4, 12, 1)

  fp.Start

  repeat
    repeat i from 0 to 3
      readTemp(i)
    waitcnt(40_000_000 + cnt)

PUB readTemp(channel) | adc_val, temp_c, temp_f, idx
'Channel = [0, 3]

  idx := 0
  adc_val := fp.FFloat(adc.average(channel, 1024))

  'Find the entry which is <= our reading
  repeat until fp.FCmp(adc_val, LONG[@adc_conversion][idx+1]) == -1
    idx++

  if idx == 0
    'return -1.0
    vfd.selectLine(channel)
    vfd.str(string("Temp: Lo"))
  else
    temp_c := fp.FDiv(fp.FSub(adc_val, LONG[@adc_conversion][idx]), fp.FSub(LONG[@adc_conversion][idx+1], LONG[@adc_conversion][idx]))
    temp_c := fp.FAdd(fp.FFloat(idx * 5 + 15), fp.FMul(5.0, temp_c))
    vfd.selectCharacter(channel, 0)
    vfd.str(string("Temp: "))
    vfd.str(fmt.FloatToFormat(temp_c, 5, 1))
    vfd.str(string(" C"))

DAT
'Lookup table of ADC values. Temp := Index * 5 + 15 degrees C -> 15..300 range
adc_conversion LONG   79.90985,  100.36895,  125.10120,  154.74334,  189.96467,  231.45450,  279.88376,  335.88673,  400.04464,  472.79601,  554.50030,  645.23974
               LONG  744.94574,  853.36507,  969.82340, 1093.61648, 1223.64721, 1358.71051, 1497.42876, 1638.36994, 1780.03614, 1920.99552, 2059.92658, 2195.58686
               LONG 2326.93965, 2453.13260, 2573.47053, 2687.56950, 2795.01873, 2895.73900, 2989.72339, 3077.04633, 3157.95862, 3232.63130, 3301.40929, 3364.61190
               LONG 3422.61261, 3475.75404, 3524.39134, 3568.87373, 3609.53971, 3646.68616, 3680.63292, 3711.64880, 3739.98093, 3765.88959, 3789.57630, 3811.24286
               LONG 3831.07623, 3849.23331, 3865.88343, 3881.14858, 3895.17052, 3908.03929, 3919.87389, 3930.76246, 3940.79693, 3950.04836, 4096.0
