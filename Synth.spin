{{
*****************************************
* Frequency Synthesizer demo v1.1       *
* Author: Beau Schwabe                  *
* Copyright (c) 2007 Parallax           *
* See end of file for terms of use.     *
*****************************************
  Original Author: Chip Gracey
  Modified by Beau Schwabe
*****************************************
}}
{
Revision History:
                  Version 1.0   -    original file created
                  
                  Version 1.1   -    For Channel "B" there was a typo in the 'Synth' object
                                     The line that reads...
                                     DIRB[Pin]~~                        'make pin output
                                     ...should read...  
                                     DIRA[Pin]~~                        'make pin output
}
PUB start(CTR_AB, Pin, Freq) | s, d, ctr, frq

  Freq := Freq #> 0 <# 128_000_000     'limit frequency range
  
  if Freq < 500_000                    'if 0 to 499_999 Hz,
    ctr := constant(%00100 << 26)      '..set NCO mode
    s := 1                             '..shift = 1
  else                                 'if 500_000 to 128_000_000 Hz,
    ctr := constant(%00010 << 26)      '..set PLL mode
    d := >|((Freq - 1) / 1_000_000)    'determine PLLDIV
    s := 4 - d                         'determine shift
    ctr |= d << 23                     'set PLLDIV
    
  frq := fraction(Freq, CLKFREQ, s)    'Compute FRQA/FRQB value
  ctr |= Pin                           'set PINA to complete CTRA/CTRB value

  if CTR_AB == "A"
     CTRA := ctr                        'set CTRA
     FRQA := frq                        'set FRQA                   
     DIRA[Pin]~~                        'make pin output
     
  if CTR_AB == "B"
     CTRB := ctr                        'set CTRB
     FRQB := frq                        'set FRQB                   
     DIRA[Pin]~~                        'make pin output

PUB stop(CTR_AB)
  if CTR_AB == "A"
     CTRA := 0                          'set CTRA                   
     
  if CTR_AB == "B"
     CTRB := 0                          'set CTRB                   
       
PRI fraction(a, b, shift) : f

  if shift > 0                         'if shift, pre-shift a or b left
    a <<= shift                        'to maintain significant bits while 
  if shift < 0                         'insuring proper result
    b <<= -shift
 
  repeat 32                            'perform long division of a/b
    f <<= 1
    if a => b
      a -= b
      f++           
    a <<= 1
DAT
{{
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}    