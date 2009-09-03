CON
  SQRT = 1
  DIV = 2
  MULT = 3
  LEN = 4
VAR
  long status, command, resultHH, resultHL 'Contiguous hub space
  long tmp1H, tmp1L, tmp2H, tmp2L  
PUB calcRapidLowTime(rate)
  return div64($0, 80_000_000, rate)
PUB calcLinearLowTime(rate, dist, pLength, tp, tpp) | ta, tb
  ta := mul64(rate * dist, 80_000_000)
  tb := getMultL

  long[tp] := ta
  long[tpp] := tb
  

  return div64(ta, tb, pLength)
PUB calcPathLength(xDist, yDist, zDist)
{ Off by <= 1 - Need to round to reduce to 0.5 }
  param1H := xDist
  param1L := yDist
  param2 := zDist

  status := 1
  command := LEN

  cognew(@entry, @status)

  repeat while status == 1

  return resultHL  
PUB sqrt64(aH, aL) : root
  param1H := aH
  param1L := aL
  param2 := 0

  status := 1
  command := SQRT
  
  cognew(@entry, @status)

  repeat while status == 1

  root := resultHL
PUB mul64(multiplier, multiplicand) : productH
  param1H := 0
  param1L := multiplier
  param2  := multiplicand

  status := 1
  command := MULT
  
  cognew(@entry, @status)

  repeat while status == 1

  productH := resultHH
PUB getMultL
  return resultHL
PUB div64(numH, numL, denom) : quotient
  param1H := numH
  param1L := numL
  param2  := denom

  status := 1
  command := DIV
  
  cognew(@entry, @status)

  repeat while status == 1

  quotient := resultHL  
DAT
        ORG 0        

entry   mov ptr, par
        add ptr, #4     'Offset of command
        rdlong t1, ptr
   
        cmp t1, #SQRT wz
  if_nz jmp #nxt1     
        call #long_sqrt
        jmp #end
nxt1    cmp t1, #DIV wz
  if_nz jmp #nxt2        
        call #long_div 
        jmp #end
nxt2    cmp t1, #MULT wz        
  if_nz jmp #nxt3      
        call #long_mult
        jmp #end
nxt3    cmp t1, #LEN wz
  if_nz jmp #kill
        call #length                

end     mov ptr, par
        add ptr, #8
        wrlong resultH, ptr    'Save result high
        add ptr, #4
        wrlong resultL, ptr    'Save result low
        mov ptr, par
        mov t1, #0        
        wrlong t1, ptr          'Status => 0

kill    cogid t1
        cogstop t1

'------------------------------------------------------------------------------
' _FAdd    fnumA = fnumA + fNumB
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB, t1
'------------------------------------------------------------------------------

_FAdd                   
                        test    flagA, #SignFlag wz     ' negate A mantissa if negative
          if_nz         neg     manA, manA
                        test    flagB, #SignFlag wz     ' negate B mantissa if negative
          if_nz         neg     manB, manB

                        mov     t1, expA                ' align mantissas
                        sub     t1, expB
                        abs     t1, t1
                        max     t1, #31
                        cmps    expA, expB wz,wc
          if_nz_and_nc  sar     manB, t1
          if_nz_and_c   sar     manA, t1
          if_nz_and_c   mov     expA, expB        

                        add     manA, manB              ' add the two mantissas
                        cmps    manA, #0 wc, nr         ' set sign of result
          if_c          or      flagA, #SignFlag
          if_nc         andn    flagA, #SignFlag
                        abs     manA, manA              ' pack result and exit
                        
_FAdd_ret               ret      

'------------------------------------------------------------------------------
' _FMul    fnumA = fnumA * fNumB
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB, t1, t2
'------------------------------------------------------------------------------

_FMul                   
          if_c          jmp     #_FMul_ret              ' check for NaN

                        xor     flagA, flagB            ' get sign of result
                        add     expA, expB              ' add exponents
                        mov     t1, #0                  ' t2 = upper 32 bits of manB
                        mov     t2, #32                 ' loop counter for multiply
                        shr     manB, #1 wc             ' get initial multiplier bit 
                                    
:multiply if_c          add     t1, manA wc             ' 32x32 bit multiply
                        rcr     t1, #1 wc
                        rcr     manB, #1 wc
                        djnz    t2, #:multiply

                        shl     t1, #3                  ' justify result and exit
                        mov     manA, t1                        
                         
_FMul_ret               ret

'------------------------------------------------------------------------------
' _FDiv    fnumA = fnumA / fNumB
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB, t1, t2
'------------------------------------------------------------------------------

_FDiv    
          if_c_or_z     mov     fnumA, NaN              ' check for NaN or divide by 0
          if_c_or_z     jmp     #_FDiv_ret
        
                        xor     flagA, flagB            ' get sign of result
                        sub     expA, expB              ' subtract exponents
                        mov     t1, #0                  ' clear quotient
                        mov     t2, #30                 ' loop counter for divide

:divide                 shl     t1, #1                  ' divide the mantissas
                        cmps    manA, manB wz,wc
          if_z_or_nc    sub     manA, manB
          if_z_or_nc    add     t1, #1
                        shl     manA, #1
                        djnz    t2, #:divide

                        mov     manA, t1                ' get result and exit

_FDiv_ret               ret
                                  
'------------------------------------------------------------------------------
' _FSqr    fnumA = sqrt(fnumA)
' changes: fnumA, flagA, expA, manA, t1, t2, t3, t4, t5 
'------------------------------------------------------------------------------

_FSqr
          if_nc         mov     fnumA, #0                ' set initial result to zero
          if_c_or_z     jmp     #_FSqr_ret               ' check for NaN or zero
                        test    flagA, #signFlag wz      ' check for negative
          if_nz         mov     fnumA, NaN               ' yes, then return NaN                       
          if_nz         jmp     #_FSqr_ret
          
                        test    expA, #1 wz             ' if even exponent, shift mantissa 
          if_z          shr     manA, #1
                        sar     expA, #1                ' get exponent of root
                        mov     t1, Bit30               ' set root value to $4000_0000                ' 
                        mov     t2, #31                 ' get loop counter

:sqrt                   or      fnumA, t1               ' blend partial root into result
                        mov     t3, #32                 ' loop counter for multiply
                        mov     t4, #0
                        mov     t5, fnumA
                        shr     t5, #1 wc               ' get initial multiplier bit
                        
:multiply if_c          add     t4, fnumA wc            ' 32x32 bit multiply
                        rcr     t4, #1 wc
                        rcr     t5, #1 wc
                        djnz    t3, #:multiply

                        cmps    manA, t4 wc             ' if too large remove partial root
          if_c          xor     fnumA, t1
                        shr     t1, #1                  ' shift partial root
                        djnz    t2, #:sqrt              ' continue for all bits
                        
                        mov     manA, fnumA             ' store new mantissa value and exit
                        shr     manA, #1

_FSqr_ret               ret


'------------------------------------------------------------------------------
' input:   fnumA        32-bit floating point value
'          fnumB        32-bit floating point value
'          fnumC        32-bit floating point value 
' output:  flagA        fnumA flag bits (Nan, Infinity, Zero, Sign)
'          expA         fnumA exponent (no bias)
'          manA         fnumA mantissa (aligned to bit 29)
'          flagB        fnumB flag bits (Nan, Infinity, Zero, Sign)
'          expB         fnumB exponent (no bias)
'          manB         fnumB mantissa (aligned to bit 29)
'          C flag       set if fnumA or fnumB is NaN
'          Z flag       set if fnumB is zero
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB, t1
'------------------------------------------------------------------------------

_Unpack3                mov     t1, fnumA               ' save A

                        mov     fnumA, fnumC            ' unpack C to A
                        call    #_Unpack
          if_c          jmp     #_Unpack2_ret           ' check for NaN

                        mov     fnumC, fnumA            ' save C variables
                        mov     flagC, flagA
                        mov     expC, expA
                        mov     manC, manA

                        mov     fnumA, fnumB            ' unpack B to A
                        call    #_Unpack
          if_c          jmp     #_Unpack2_ret           ' check for NaN

                        mov     fnumB, fnumA            ' save B variables
                        mov     flagB, flagA
                        mov     expB, expA
                        mov     manB, manA

                        mov     fnumA, t1               ' unpack A
                        call    #_Unpack
                        cmp     manB, #0 wz             ' set Z flag                      
_Unpack2_ret            ret

'------------------------------------------------------------------------------
' input:   fnumA        32-bit floating point value 
' output:  flagA        fnumA flag bits (Nan, Infinity, Zero, Sign)
'          expA         fnumA exponent (no bias)
'          manA         fnumA mantissa (aligned to bit 29)
'          C flag       set if fnumA is NaN
'          Z flag       set if fnumA is zero
' changes: fnumA, flagA, expA, manA
'------------------------------------------------------------------------------

_Unpack                 mov     flagA, fnumA            ' get sign
                        shr     flagA, #31
                        mov     manA, fnumA             ' get mantissa
                        and     manA, Mask23
                        mov     expA, fnumA             ' get exponent
                        shl     expA, #1
                        shr     expA, #24 wz
          if_z          jmp     #:zeroSubnormal         ' check for zero or subnormal
                        cmp     expA, #255 wz           ' check if finite
          if_nz         jmp     #:finite
                        mov     fnumA, NaN              ' no, then return NaN
                        mov     flagA, #NaNFlag
                        jmp     #:exit2        

:zeroSubnormal          or      manA, expA wz,nr        ' check for zero
          if_nz         jmp     #:subnorm
                        or      flagA, #ZeroFlag        ' yes, then set zero flag
                        neg     expA, #150              ' set exponent and exit
                        jmp     #:exit2
                                 
:subnorm                shl     manA, #7                ' fix justification for subnormals  
:subnorm2               test    manA, Bit29 wz
          if_nz         jmp     #:exit1
                        shl     manA, #1
                        sub     expA, #1
                        jmp     #:subnorm2

:finite                 shl     manA, #6                ' justify mantissa to bit 29
                        or      manA, Bit29             ' add leading one bit
                        
:exit1                  sub     expA, #127              ' remove bias from exponent
:exit2                  test    flagA, #NaNFlag wc      ' set C flag
                        cmp     manA, #0 wz             ' set Z flag
_Unpack_ret             ret       

'------------------------------------------------------------------------------
' input:   flagA        fnumA flag bits (Nan, Infinity, Zero, Sign)
'          expA         fnumA exponent (no bias)
'          manA         fnumA mantissa (aligned to bit 29)
' output:  fnumA        32-bit floating point value
' changes: fnumA, flagA, expA, manA 
'------------------------------------------------------------------------------

_Pack                   cmp     manA, #0 wz             ' check for zero                                        
          if_z          mov     expA, #0
          if_z          jmp     #:exit1

:normalize              shl     manA, #1 wc             ' normalize the mantissa 
          if_nc         sub     expA, #1                ' adjust exponent
          if_nc         jmp     #:normalize
                      
                        add     expA, #2                ' adjust exponent
                        add     manA, #$100 wc          ' round up by 1/2 lsb
          if_c          add     expA, #1

                        add     expA, #127              ' add bias to exponent
                        mins    expA, Minus23
                        maxs    expA, #255
 
                        cmps    expA, #1 wc             ' check for subnormals
          if_nc         jmp     #:exit1

:subnormal              or      manA, #1                ' adjust mantissa
                        ror     manA, #1

                        neg     expA, expA
                        shr     manA, expA
                        mov     expA, #0                ' biased exponent = 0

:exit1                  mov     fnumA, manA             ' bits 22:0 mantissa
                        shr     fnumA, #9
                        movi    fnumA, expA             ' bits 23:30 exponent
                        shl     flagA, #31
                        or      fnumA, flagA            ' bit 31 sign            
_Pack_ret               ret

'-------------------- constant values -----------------------------------------

Zero                    long    0                       ' constants
One                     long    $3F80_0000
NaN                     long    $7FFF_FFFF
Minus23                 long    -23
Mask23                  long    $007F_FFFF
Mask29                  long    $1FFF_FFFF
Bit16                   long    $0001_0000
Bit29                   long    $2000_0000
Bit30                   long    $4000_0000
Bit31                   long    $8000_0000

'-------------------- local variables -----------------------------------------

t1                      res     1                       ' temporary values
t2                      res     1
t3                      res     1
t4                      res     1
t5                      res     1
t6                      res     1
t7                      res     1
t8                      res     1

status                  res     1                       ' last compare status

fnumA                   res     1                       ' floating point A value
flagA                   res     1
expA                    res     1
manA                    res     1

fnumB                   res     1                       ' floating point B value
flagB                   res     1
expB                    res     1
manB                    res     1

fnumC                   res     1                       ' floating point C value
flagC                   res     1
expC                    res     1
manC                    res     1

      FIT 496 