CON
DIG_0           = $01
DIG_1           = $02     
DIG_2           = $03     
DIG_3           = $04     
DECODE_MODE     = $09     
INTENSITY       = $0A     
SCAN_LIMIT      = $0B     
SHUTDOWN        = $0C     
DISP_TEST       = $0F     

ENABLE          = $01
DISABLE         = $00

OBJ
  pins : "Pins"

PUB main
{  writeSPI(TEST, DISABLE, chip);
        writeSPI(SHUTDOWN, ENABLE, chip);
        
        writeSPI(DECODE_MODE, 0x07, chip);
//      writeSPI(DECODE_MODE, 0xFF, chip);
        writeSPI(SCAN_LIMIT, 0x04, chip);
        writeSPI(INTENSITY, 0xFF, chip);

//      writeSPI(DIG_3, 0x39, chip); //F character
        writeSPI(DIG_3, 0x4E, chip); //C character}
   repeat
      write($0f01)
'  write((SHUTDOWN << 8) | ENABLE)


          
PUB write (data) | bitmask
  outa[24] := 0
  outa[9] := 0
  outa[6] := 0
  
  dira[24] := 0 
  dira[24] := 1

  bitmask := $8000

  repeat while bitmask > 0
    if (data & bitmask)
        dira[9] := 0
    else
        dira[9] := 1

    dira[6] := 0
    dira[6] := 1

     bitmask := bitmask >> 1   

  dira[24] := 0               

  