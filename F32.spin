{{
        F32 : a tuned-up version of Float32Full in 1 cog

        Modified by Jonathan (lonesock) to try to fit all functionality
        into a single cog, and speed-up the routines where possible.

        Some functions have had some of the corner-cases corrected.

        Features:
        * prop resources:       1 cog, ~630 longs (BST can remove unused Spin code!)
        * faster:               _Pack, Add, Sub, Sqr, Sin, Cos, Tan, Float, Exp*, Log*, Pow, Mul, Div
        * added funcs:          Exp2, Log2 (Spin calling code only, no cog bloat),
                                FMod, ATan, ATan2, ACos, ASin, Floor, Ceil (from Float32A),
                                FloatTrunc, FloatRound, UintTrunc (added code to the cog)
        * more accurate:        ATan, ATan2, ACos, ASin

        Still Needed / Desired:
        * MORE TESTING!! (hint hint [8^)
        * User-defined function mechanism (from Float32A)...does anyone use this?

        Changelog:
        * Sept 29, 2010 - fixed some comments, added UintTrunc, only 4 longs free [8^(
        * Sept 28, 2010 - added FloatTrunc & FloatRound, converted to all ASCII with CRLF end of line.
        * Sept 27, 2010 - faster interpolation, CORDIC faster (uses full table), Tan faster (reuses some cals from Sin in Cos) - 26 longs free
        * Sept 24, 2010 - fixed the trig functions (had a bug in my table interpolation code)
        * Sept 21, 2010 - faster multiply and divide - 26 longs free
        * Sept 20, 2010 - added in all the functionality from Float32Full - 14 longs free
        * Sept 15, 2010 - fixed race condition on startup, 111 longs free
        * Sept 14, 2010 - fixed Exp*, sped up Exp*, Log*, Pow, Cos and Sin again
        * Sept 13, 2010 (PM) - fixed Trunc and Round to now do the right thing for large integers. 83 longs available
        * Sept 13, 2010 (AM) - new calling convention. 71 longs available in-Cog
}}
{{
-------------------------------------------------
File: Float32.spin
Version: 1.5
Copyright (c) 2009 Parallax, Inc.
See end of file for terms of use.

Author: Cam Thompson                                      
-------------------------------------------------
}}

{
HISTORY:
  This object provides IEEE 754 compliant 32-bit floating point math routines implemented in assembler.
  It requires one cog.

  The following table summarizes the differences between: FloatMath, Float32, and Float32Full.
   +--------------------------+------------+-----------+-----------+
   |                          | FloatMath  |  Float32  |Float32Full|
   +--------------------------+------------+-----------+-----------+
   | Cogs required:           |     0      |     1     |     2     |
   +--------------------------+------------+-----------+-----------+
   | Execution Speed:         |    Slow    |    Fast   |    Fast   |
   |   e.g. FADD (usec)       |    371     |     39    |     39    |
   +--------------------------+------------+-----------+-----------+ 
   | Methods:                 |            |           |           |
   |   FAdd, FSub, FMul, FDiv |     *      |     *     |     *     |
   |   FFloat, FTrunc, FRound |     *      |     *     |     *     |
   |   FSqr, FNeg, FAbs       |     *      |     *     |     *     |
   +--------------------------+------------+-----------+-----------+ 
   |   Sin, Cos, Tan          |            |     *     |     *     |
   |   Radians, Degrees       |            |     *     |     *     |
   |   Log, Log10, Exp, Exp10 |            |     *     |     *     |
   |   Pow, Frac              |            |     *     |     *     |
   |   FMod                   |            |     *     |     *     |
   |   Fmin, Fmax             |            |     *     |     *     |
   +--------------------------+------------+-----------+-----------+ 
   |   FMod                   |            |           |     *     |
   |   ASin, ACos, ATan       |            |           |     *     |
   |   ATan2                  |            |           |     *     |    
   |   Floor, Ceil            |            |           |     *     |
   |   FFunc                  |            |           |     *     |
   +--------------------------+------------+-----------+-----------+
  Additional documentation is provided in the file: Propeller Floating Point.pdf
   
  V1.5 - July 14, 2009
  * added comments to Spin methods
  * removed sendCmd comments
  V1.4 - September 25, 2007
  * fixed problem in loadTable routine used by Log and Exp functions
  V1.3 - Apr 1, 2007
  * fixed Sin/Cos interpolation code
  * moved FMod routine from Float32 to Float32A
  V1.2 - March 26, 2007
  * fixed Pow to handle negative base values
  V1.1 - Oct 5, 2006
  * corrected constant value for Radians and Degrees
  V1.0 - May 17, 2006
  * original version

USAGE:
  * call start first.
  * Float32 uses one cog for its operation.   
}

CON
  SignFlag      = $1
  ZeroFlag      = $2
  NaNFlag       = $8
  
VAR

  long  f32_Cmd, f32_RetAB_ptr
  byte  cog
  
PUB start
{{Start start floating point engine in a new cog.
  Returns:     True (non-zero) if cog started, or False (0) if no cog is available.}}

  stop
  f32_Cmd := 0
  return cog := cognew(@f32_entry, @f32_Cmd) + 1

PUB stop
{{Stop floating point engine and release the cog.}}

  if cog
    cogstop(cog~ - 1)
         
PUB FAdd(a, b)
{{Addition: result = a + b
  Parameters:
    a        32-bit floating point value
    b        32-bit floating point value
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFAdd
  repeat while f32_Cmd
          
PUB FSub(a, b)
{{Subtraction: result = a - b
  Parameters:
    a        32-bit floating point value
    b        32-bit floating point value
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFSub
  repeat while f32_Cmd
  
PUB FMul(a, b)
{{Multiplication: result = a * b
  Parameters:
    a        32-bit floating point value
    b        32-bit floating point value
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFMul
  repeat while f32_Cmd
          
PUB FDiv(a, b)
{{Division: result = a / b
  Parameters:
    a        32-bit floating point value
    b        32-bit floating point value
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFDiv
  repeat while f32_Cmd

PUB FFloat(n)
{{Convert integer to floating point.
  Parameters:
    n        32-bit integer value
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFFloat
  repeat while f32_Cmd

PUB FTrunc(a) | b
{{Convert floating point to integer (with truncation).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit integer value }}

  b := %000
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFTruncRound
  repeat while f32_Cmd

PUB UintTrunc(a)
{{Convert floating point to unsigned integer (with truncation).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit unsigned integer value }}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdUintTrunc
  repeat while f32_Cmd

PUB FRound(a) | b
{{Convert floating point to integer (with rounding).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit integer value }}

  b := %001
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFTruncRound
  repeat while f32_Cmd

PUB FloatTrunc(a) | b
{{Convert floating point to whole number (with truncation).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value }}

  b := %010
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFTruncRound
  repeat while f32_Cmd

PUB FloatRound(a) | b
{{Convert floating point to whole number (with rounding).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value }}

  b := %011
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFTruncRound
  repeat while f32_Cmd

PUB FSqr(a)
{{Square root.
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value }}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFSqr
  repeat while f32_Cmd

PUB FCmp(a, b)
{{Floating point comparison.
  Parameters:
    a        32-bit floating point value
    b        32-bit floating point value
  Returns:   32-bit integer value
             -1 if a < b
              0 if a == b
              1 if a > b}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFCmp
  repeat while f32_Cmd

PUB Sin(a)
{{Sine of an angle. 
  Parameters:
    a        32-bit floating point value (angle in radians)
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFSin
  repeat while f32_Cmd

PUB Cos(a)
{{Cosine of an angle.
  Parameters:
    a        32-bit floating point value (angle in radians)
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFCos
  repeat while f32_Cmd

PUB Tan(a)
{{Tangent of an angle.
  Parameters:
    a        32-bit floating point value (angle in radians)
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFTan
  repeat while f32_Cmd

PUB Log(a) | b
{{Logarithm (base e).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}

  b             := 1.442695041  ' convert base 2 to base e
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFLog2
  repeat while f32_Cmd

PUB Log2(a) | b
{{Logarithm (base 2).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}

  b             := 0            ' 0 is a flag to skip the base conversion
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFLog2
  repeat while f32_Cmd

PUB Log10(a) | b
{{Logarithm (base 10).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}

  b             := 3.321928095  ' convert base 2 to base 10
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFLog2
  repeat while f32_Cmd

PUB Exp(a) | b
{{Exponential (e raised to the power a).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}

  b             := 1.442695041  ' convert base 2 to base e
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFExp2
  repeat while f32_Cmd

PUB Exp2(a) | b
{{Exponential (e raised to the power a).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}

  b             := 0            ' 0 is a flag to skip the base conversion
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFExp2
  repeat while f32_Cmd

PUB Exp10(a) | b
{{Exponential (10 raised to the power a).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}

  b             := 3.321928095  ' convert base 2 to base 10
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFExp2
  repeat while f32_Cmd

PUB Pow(a, b)
{{Power (a to the power b).
  Parameters:
    a        32-bit floating point value
    b        32-bit floating point value  
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFPow
  repeat while f32_Cmd

PUB Frac(a)
{{Fraction (returns fractional part of a).
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFFrac
  repeat while f32_Cmd

PUB FNeg(a)
{{Negate: result = -a.
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}
  
  return a ^ $8000_0000

PUB FAbs(a)
{{Absolute Value: result = |a|.
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}
  
  return a & $7FFF_FFFF
  
PUB Radians(a) | b
{{Convert to radians
  Parameters:
    a        32-bit floating point value (angle in degrees)
  Returns:   32-bit floating point value (angle in radians)}}
  
  b := constant(pi / 180.0)
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFMul
  repeat while f32_Cmd

PUB Degrees(a) | b
{{Convert to degrees
  Parameters:
    a        32-bit floating point value (angle in radians)
  Returns:   32-bit floating point value (angle in degrees)}}
  
  b := constant(180.0 / pi)
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFMul
  repeat while f32_Cmd

PUB FMin(a, b)
{{Minimum: result = the minimum value a or b.
  Parameters:
    a        32-bit floating point value
    b        32-bit floating point value  
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFCmp
  repeat while f32_Cmd
  if result < 0
    return a
  return b
  
PUB FMax(a, b)
{{Maximum: result = the maximum value a or b.
  Parameters:
    a        32-bit floating point value
    b        32-bit floating point value  
  Returns:   32-bit floating point value}}

  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFCmp
  repeat while f32_Cmd
  if result < 0
    return b
  return a

{+-------------------+
 | Float32A routines |
 +-------------------+}

PUB FMod(a, b)
{{Floating point remainder: result = the remainder of a / b.
  Parameters:
    a        32-bit floating point value
    b        32-bit floating point value  
  Returns:   32-bit floating point value}}
  
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFMod
  repeat while f32_Cmd

PUB ASin(a) | b
{{Arc Sine of a. 
  Parameters:
    a        32-bit floating point value (|a| must be < 1)
  Returns:   32-bit floating point value (angle in radians)}}

  b := 1
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdASinCos
  repeat while f32_Cmd

PUB ACos(a) | b
{{Arc Cosine of a. 
  Parameters:
    a        32-bit floating point value (|a| must be < 1)
  Returns:   32-bit floating point value (angle in radians)
             if |a| > 1, NaN is returned}}

  b := 0
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdASinCos
  repeat while f32_Cmd

PUB ATan(a) | b
{{Arc Tangent of a. 
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value (angle in radians)}}

  b := 1.0
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdATan2
  repeat while f32_Cmd

PUB ATan2(a, b)
{{Arc Tangent of a / b. 
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value (angle in radians)}}
  
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdATan2
  repeat while f32_Cmd

PUB Floor(a)
{{Calculate the floating point value of the nearest integer <= a. 
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}
  
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdFloor
  repeat while f32_Cmd

PUB Ceil(a)
{{Calculate the floating point value of the nearest integer >= a. 
  Parameters:
    a        32-bit floating point value
  Returns:   32-bit floating point value}}
  
  f32_RetAB_ptr := @result
  f32_Cmd       := cmdCeil
  repeat while f32_Cmd                           

DAT

'---------------------------
' Assembly language routines
'---------------------------
                        org     0
f32_entry               ' set ret_ptr_ptr to the long after par (it's initialized as 4)
t1                      add     ret_ptr_ptr, par        ' doubled up as temporary variable t1

                        ' try to keep 2 or fewer instructions between rd/wrlong
getCommand              rdlong  :execCmd, par wz        ' wait for command to be non-zero, and store it in the call location
              if_z      jmp     #getCommand

                        rdlong  ret_ptr, ret_ptr_ptr    ' get the pointer to the return value ("@result")
                        add     ret_ptr, #4

                        rdlong  fNumA, ret_ptr          ' fnumA is the long after "result"
                        add     ret_ptr, #4

                        rdlong  fNumB, ret_ptr          ' fnumB is the long after fnumA
                        sub     ret_ptr, #8

:execCmd                nop                             ' execute command, which was replaced by getCommand

:finishCmd              wrlong  fnumA, ret_ptr          ' store the result (2 longs before fnumB)
                        mov     t1, #0                  ' zero out the command register
                        wrlong  t1, par                 ' clear command status
                        jmp     #getCommand             ' wait for next command

'------------------------------------------------------------------------------
' _FAdd    fnumA = fnumA + fNumB
' _FAddI   fnumA = fnumA + {Float immediate}
' _FSub    fnumA = fnumA - fNumB
' _FSubI   fnumA = fnumA - {Float immediate}
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB, t1
'------------------------------------------------------------------------------

_FSub                   xor     fnumB, Bit31            ' negate B
                        jmp     #_FAdd                  ' add values

_FAdd                   call    #_Unpack2               ' unpack two variables                    
          if_c_or_z     jmp     #_FAdd_ret              ' check for NaN or B = 0

                        test    flagA, #SignFlag wz     ' negate A mantissa if negative
          if_nz         neg     manA, manA
                        test    flagB, #SignFlag wz     ' negate B mantissa if negative
          if_nz         neg     manB, manB

                        mov     t1, expA                ' align mantissas
                        sub     t1, expB
                        abs     t1, t1          wc
                        max     t1, #31
              if_nc     sar     manB, t1
              if_c      sar     manA, t1
              if_c      mov     expA, expB

                        add     manA, manB              ' add the two mantissas
                        abs     manA, manA      wc      ' store the absolte value,
                        muxc    flagA, #SignFlag        ' and flag if it was negative

                        call    #_Pack                  ' pack result and exit
_FSub_ret
_FAdd_ret               ret      

'------------------------------------------------------------------------------
' _FMul    fnumA = fnumA * fNumB
' _FMulI   fnumA = fnumA * {Float immediate}
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB, t1, t2
'------------------------------------------------------------------------------

_FMul                   call    #_Unpack2               ' unpack two variables
              if_c      jmp     #_FMul_ret              ' check for NaN

                        xor     flagA, flagB            ' get sign of result
                        add     expA, expB              ' add exponents

                        ' new version of multiply, faster
                        mov     t1, #0                  ' t1 is my accumulator
                        mov     t2, #24                 ' loop counter for multiply (only do the bits needed...23 + implied 1)
                        shr     manB, #6                ' start by right aligning the B mantissa

:multiply               shr     t1, #1                  ' shift the previous accumulation down by 1
                        shr     manB, #1 wc             ' get multiplier bit
              if_c      add     t1, manA                ' if the bit was set, add in the multiplicand
                        djnz    t2, #:multiply          ' go back for more
                        mov     manA, t1                ' yes, that's my final answer.

                        call    #_Pack

_FMul_ret               ret

'------------------------------------------------------------------------------
' _FDiv    fnumA = fnumA / fNumB
' _FDivI   fnumA = fnumA / {Float immediate}
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB, t1, t2
'------------------------------------------------------------------------------

_FDiv                   call    #_Unpack2               ' unpack two variables
          if_c_or_z     mov     fnumA, NaN              ' check for NaN or divide by 0
          if_c_or_z     jmp     #_FDiv_ret
        
                        xor     flagA, flagB            ' get sign of result
                        sub     expA, expB              ' subtract exponents

                        ' slightly faster division, using 26 passes instead of 30
                        mov     t1, #0                  ' clear quotient
                        mov     t2, #26                 ' loop counter for divide (need 24, plus 2 for rounding)

:divide                 ' divide the mantissas
                        cmpsub  manA, manB      wc
                        rcl     t1, #1
                        shl     manA, #1
                        djnz    t2, #:divide
                        shl     t1, #4                  ' align the result (we did 26 instead of 30 iterations)

                        mov     manA, t1                ' get result and exit
                        call    #_Pack

_FDiv_ret               ret

'------------------------------------------------------------------------------
' _FFloat  fnumA = float(fnumA)
' changes: fnumA, flagA, expA, manA
'------------------------------------------------------------------------------
_FFloat                 abs     manA, fnumA     wc,wz   ' get |integer value|
              if_z      jmp     #_FFloat_ret            ' if zero, exit
                        mov     flagA, #0               ' set the sign flag
                        muxc    flagA, #SignFlag        ' depending on the integer's sign
                        mov     expA, #29               ' set my exponent
                        call    #_Pack                  ' pack and exit
_FFloat_ret             ret

'------------------------------------------------------------------------------
' _FTrunc  fnumA = fix(fnumA)
' _FRound  fnumA = fix(round(fnumA))
' fnumB controls the output format:
'       %00 = integer, truncate
'       %01 = integer, round
'       %10 = float, truncate
'       %11 = float, round
' changes: fnumA, flagA, expA, manA, t1 
'------------------------------------------------------------------------------

_FTruncRound            mov     t1, fnumA               ' grab a copy of the input
                        call    #_Unpack                ' unpack floating point value

                        ' Are we going for float or integer?
                        cmpsub  fnumB, #%10     wc      ' clear bit 1 and set the C flag if it was a 1
                        rcl     t2, #1
                        and     t2, #1          wz      ' Z now signified integer output

                        shl     manA, #2                ' left justify mantissa
                        sub     expA, #30               ' our target exponent is 30
                        abs     expA, expA      wc      ' adjust for exponent sign, and track if it was negative
                          
              if_z_and_nc mov   manA, NaN               ' integer output, and it's too large for us to handle
              if_z_and_nc jmp   #:check_sign
              
              if_nz_and_nc mov  fnumA, t1                ' float output, and we're already all integer
              if_nz_and_nc jmp  #_FTruncRound_ret
                        
                        ' well, I need to kill off some bits, so let's do it
                        max     expA, #31       wc
                        shr     manA, expA
              if_c      add     manA, fnumB             ' round up 1/2 lsb if desired, and if it isn't supposed to be 0! (if expA was > 31)
                        shr     manA, #1

              if_z      jmp     #:check_sign            ' integer output?

                        mov     expA, #29
                        call    #_Pack
                        jmp     #_FTruncRound_ret

:check_sign             test    flagA, #signFlag wz     ' check sign and exit
                        negnz   fnumA, manA

_FTruncRound_ret        ret


'------------------------------------------------------------------------------
' _UintTrunc  fnumA = uint(fnumA)
'------------------------------------------------------------------------------
_UintTrunc              call    #_Unpack
                        mov     fnumA, #0
                        test    flagA, #SignFlag wc
              if_c_or_z jmp     #_UintTrunc_ret         ' if the input number was negative or zero, we're done
                        shl     manA, #2                ' left justify mantissa
                        sub     expA, #31               ' our target exponent is 31
                        abs     expA, expA      wc,wz
              if_a      neg     fnumA, #1               ' if we needed to shift left, we're already maxed out
              if_be     cmp     expA, #32       wc      ' otherwise, if we need to shift right by more than 31, the answer is 0
              if_c      shr     manA, expA              ' OK, shift it down
              if_c      mov     fnumA, manA
_UintTrunc_ret          ret

                                  
'------------------------------------------------------------------------------
' _FSqr    fnumA = sqrt(fnumA)
' changes: fnumA, flagA, expA, manA, t1, t2, t3, t4, t5 
'------------------------------------------------------------------------------
_FSqr                   call    #_Unpack                 ' unpack floating point value
          if_c_or_z     jmp     #_FSqr_ret               ' check for NaN or zero
                        test    flagA, #signFlag wz      ' check for negative
          if_nz         mov     fnumA, NaN               ' yes, then return NaN                       
          if_nz         jmp     #_FSqr_ret

                        sar     expA, #1 wc             ' if odd exponent, shift mantissa
          if_c          shl     manA, #1
                        add     expA, #1
                        mov     t2, #29

                        mov     fnumA, #0               ' set initial result to zero
:sqrt                   ' what is the delta root^2 if we add in this bit?
                        mov     t3, fnumA
                        shl     t3, #2
                        add     t3, #1
                        shl     t3, t2
                        ' is the remainder >= delta?
                        cmpsub  manA, t3        wc
                        rcl     fnumA, #1
                        shl     manA, #1
                        djnz    t2, #:sqrt
                        
                        mov     manA, fnumA             ' store new mantissa value and exit
                        call    #_Pack
_FSqr_ret               ret

'------------------------------------------------------------------------------
' _FCmp    set Z and C flags for fnumA - fNumB
' changes: status, t1
'------------------------------------------------------------------------------

_FCmp                   mov     t1, fnumA               ' compare signs
                        xor     t1, fnumB
                        and     t1, Bit31 wz
          if_z          jmp     #:cmp1                  ' same, then compare magnitude
          
                        mov     t1, fnumA               ' check for +0 or -0 
                        or      t1, fnumB
                        andn    t1, Bit31 wz,wc
          if_z          jmp     #:exit
                    
                        test    fnumA, Bit31 wc         ' compare signs
                        jmp     #:exit

:cmp1                   test    fnumA, Bit31 wz         ' check signs
          if_nz         jmp     #:cmp2
                        cmp     fnumA, fnumB wz,wc
                        jmp     #:exit

:cmp2                   cmp     fnumB, fnumA wz,wc      ' reverse test if negative

:exit                   mov     fnumA, #1               ' if fnumA > fnumB, t1 = 1
          if_c          neg     fnumA, fnumA            ' if fnumA < fnumB, t1 = -1
          if_z          mov     fnumA, #0               ' if fnumA = fnumB, t1 = 0
_FCmp_ret               ret


'------------------------------------------------------------------------------
' new table lookup code
' Inputs
' t1 = 31-bit number: 1-bit 0, then 11-bits real, then 20-bits fraction (allows the sine table to use the top bit)
' t2 = table base address
' Outputs
' t1 = 30-bit interpolated number
' Modifies
' t1, t2, t3, t4
'------------------------------------------------------------------------------
_Table_Interp           ' store the fractional part
                        mov     t4, t1                  ' will store reversed so a SAR will shift the value and get a bit
                        rev     t4, #12                 ' ignore the top 12 bits, and reverse the rest
                        ' align the input number to get the table offset, multiplied by 2
                        shr     t1, #19
                        add     t2, t1
                        ' read the 2 intermediate values, and scale them for interpolation
                        rdword  t1, t2
                        shl     t1, #14
                        add     t2, #2
                        rdword  t2, t2
                        shl     t2, #14
                        ' interpolate
                        sub     t2, t1                  ' change from 2 points to delta
                        movs    t2, t4                  ' make the low 9 bits the multiplier (reversed)
                        mov     t3, #9                  ' do 9 steps
:interp                 sar     t2, #1          wc      ' divide the delta by 2, and get the MSB multiplier bit
              if_c      add     t1, t2                  ' if the multiplier bit was 1, add in the shifter delta
                        djnz    t3, #:interp            ' keep going, 9 times around
                        ' done, and the answer is in t1, bit 29 aligned
_Table_Interp_ret       ret


'------------------------------------------------------------------------------
' _Sin     fnumA = sin(fnumA)
' _Cos     fnumA = cos(fnumA)
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB
' changes: t1, t2, t3, t4, t5, t6
'------------------------------------------------------------------------------
OneOver2Pi              long    1.0 / (2.0 * pi)        ' I need this constant to get the fractional angle

_Cos                    mov     t4, bit29               ' adjust sine to cosine at the last possible minute by adding 90 degrees
                        andn    fnumA, bit31            ' nuke the sign bit
                        jmp     #_SinCos_cont

_Sin                    mov     t4, #0                  ' just sine, and keep my sign bit

_SinCos_cont            mov     fnumB, OneOver2Pi
                        call    #_FMul                  ' rescale angle from [0..2pi] to [0..1]

                        ' now, work with the raw value
                        call    #_Unpack

                        ' get the whole and fractional bits
                        add     expA, #2                ' bias the exponent by 3 so the resulting data will be 31-bit aligned
                        abs     expA, expA      wc      ' was the exponent positive or negative?
                        max     expA, #31               ' limit to 31, otherwise we do weird wrapping things
              if_c      shr     manA, expA              ' -exp: shift right to bring down to 1.0
              if_nc     shl     manA, expA              ' +exp: shift left to throw away the high bits

                        mov     t6, manA                ' store the address in case Tan needs it

                        add     manA, t4                ' adjust for cosine?

_resume_Tan             test    manA, bit29     wz
                        negnz   t1, manA
                        shl     t1, #2

                        mov     t2, SineTable
                        call    #_Table_Interp

                        ' rebuild the number
                        test    manA, bit30     wz      ' check if we're in quadrant 3 or 4
                        abs     manA, t1                ' move my number into the mantissa
                        shr     manA, #16               ' but the table went to $FFFF, so scale up a bit to
                        addabs  manA, t1                ' get to &10000
              if_nz     xor     flagA, #SignFlag        ' invert my sign bit, if the mantissa would have been negative (quad 3 or 4)
                        neg     expA, #1                ' exponent is -1
                        call    #_Pack

_resume_Tan_ret
_Cos_ret
_Sin_ret                ret

'------------------------------------------------------------------------------
' _Tan   fnumA = tan(fnumA)
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB
' changes: t1, t2, t3, t4, t5, t6, t7, t8
'------------------------------------------------------------------------------

_Tan                    call    #_Sin
                        mov     t7, fnumA
                        ' skip the angle normalizing, much faster
                        mov     manA, t6                ' was manA for Sine
                        add     manA, bit29             ' add in 90 degrees
                        call    #_resume_Tan            ' go back and recompute the float
                        mov     fnumB, fnumA            ' move Cosine into fnumB
                        mov     fnumA, t7               ' move Sine into fnumA
                        call    #_FDiv                  ' divide
_Tan_ret                ret


'------------------------------------------------------------------------------
' _Log2    fnumA = log (base 2) fnumA, then divided by fnumB to change bases
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB, t1, t2, t3, t5, t6
'------------------------------------------------------------------------------
_Log2                   call    #_Unpack                ' unpack variable
          if_z_or_c     jmp     #:exitNaN               ' if NaN or <= 0, return NaN
                        test    flagA, #SignFlag wz
          if_nz         jmp     #:exitNaN

                        mov     t1, manA
                        shl     t1, #3
                        shr     t1, #1
                        mov     t2, LogTable
                        call    #_Table_Interp
                        ' store the interpolated table lookup
                        mov     manA, t1
                        shr     manA, #5                  ' clear the top 7 bits (already 2 free
                        ' process the exponent
                        abs     expA, expA      wc
                        muxc    flagA, #SignFlag
                        ' recombine exponent into the mantissa
                        shl     expA, #25
                        negc    manA, manA
                        add     manA, expA
                        mov     expA, #4
                        ' make it a floating point number
                        call    #_Pack
                        ' convert the base
                        cmp     fnumB, #0    wz         ' check that my divisor isn't 0 (which flags that we're doing log2)
              if_nz     call    #_FDiv                  ' convert the base (unless fnumB was 0)
                        jmp     #_Log2_ret

:exitNaN                mov     fnumA, NaN              ' return NaN
_Log2_ret               ret

'------------------------------------------------------------------------------
' _Exp     fnumA = e ** fnumA
' _Exp10   fnumA = 10 ** fnumA
' _Exp2    fnumA = 2 ** fnumA
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB
' changes: t1, t2, t3, t4, t5
'------------------------------------------------------------------------------
                        ' 1st off, convert the base
_Exp2                   cmp     fnumB, #0       wz
              if_nz     call    #_FMul

                        call    #_Unpack
                        shl     manA, #2                ' left justify mantissa
                        mov     t1, expA                ' copy the local exponent

                        '        OK, get the whole number
                        sub     t1, #30                 ' our target exponent is 31
                        abs     expA, t1      wc        ' adjust for exponent sign, and track if it was negative
              if_c      jmp     #:cont_Exp2

                        ' handle this case depending on the sign
                        test    flagA, #signFlag wz
              if_z      mov     fnumA, NaN              ' nope, was positive, bail with NaN (happens to be the largest positive integer)
              if_nz     mov     fnumA, #0
                        jmp     #_Exp2_ret

:cont_Exp2              mov     t2, manA
                        max     expA, #31
                        shr     t2, expA
                        shr     t2, #1
                        mov     expA, t2

                        ' get the fractional part
                        add     t1, #31
                        abs     t2, t1          wc
              if_c      shr     manA, t2
              if_nc     shl     manA, t2

                        ' do the table lookup
                        mov     t1, manA
                        shr     t1, #1
                        mov     t2, ALogTable
                        call    #_Table_Interp

                        ' store a copy of the sign
                        mov     t6, flagA

                        ' combine
                        mov     manA, t1
                        or      manA, bit30
                        sub     expA, #1
                        mov     flagA, #0

                        call    #_Pack

                        test    t6, #signFlag wz        ' check sign and store this back in the exponent
              if_z      jmp     #_Exp2_ret
                        mov     fnumB, fnumA            ' yes, then invert
                        mov     fnumA, One
                        call    #_FDiv

_Exp2_ret               ret

'------------------------------------------------------------------------------
' _Pow     fnumA = fnumA raised to power fnumB
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB
'          t1, t2, t3, t5, t6, t7
'------------------------------------------------------------------------------

_Pow                    mov     t7, fnumA wc            ' save sign of result
          if_nc         jmp     #:pow3                  ' check if negative base

                        mov     fnumA, fnumB            ' check exponent
                        call    #_Unpack
                        mov     fnumA, t7               ' restore base
          if_z          jmp     #:pow2                  ' check for exponent = 0
          
                        test    expA, Bit31 wz          ' if exponent < 0, return NaN
          if_nz         jmp     #:pow1

                        max     expA, #23               ' check if exponent = integer
                        shl     manA, expA    
                        and     manA, Mask29 wz, nr                         
          if_z          jmp     #:pow2                  ' yes, then check if odd
          
:pow1                   mov     fnumA, NaN              ' return NaN
                        jmp     #_Pow_ret

:pow2                   test    manA, Bit29 wz          ' if odd, then negate result
          if_z          andn    t7, Bit31

:pow3                   andn    fnumA, Bit31            ' get |fnumA|
                        mov     t6, fnumB               ' save power
                        call    #_Log2                  ' get log of base
                        mov     fnumB, t6               ' multiply by power
                        call    #_FMul
                        call    #_Exp2                  ' get result      

                        test    t7, Bit31 wz            ' check for negative
          if_nz         xor     fnumA, Bit31
_Pow_ret                ret

'------------------------------------------------------------------------------
' _Frac fnumA = fractional part of fnumA
' changes: fnumA, flagA, expA, manA
'------------------------------------------------------------------------------

_Frac                   call    #_Unpack                ' get fraction
                        test    expA, Bit31 wz          ' check for exp < 0 or NaN
          if_c_or_nz    jmp     #:exit
                        max     expA, #23               ' remove the integer
                        shl     manA, expA    
                        and     manA, Mask29
                        mov     expA, #0                ' return fraction

:exit                   call    #_Pack
                        andn    fnumA, Bit31
_Frac_ret               ret


'------------------------------------------------------------------------------
' input:   fnumA        32-bit floating point value
'          fnumB        32-bit floating point value 
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

_Unpack2                mov     t1, fnumA               ' save A
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

                        sub     expA, #380              ' take us out of the danger range for djnz
:normalize              shl     manA, #1 wc             ' normalize the mantissa
          if_nc         djnz    expA, #:normalize       ' adjust exponent and jump

                        add     manA, #$100 wc          ' round up by 1/2 lsb

                        addx    expA, #(380 + 127 + 2)  ' add bias to exponent, account for rounding (in flag C, above)
                        mins    expA, Minus23
                        maxs    expA, #255

                        abs     expA, expA wc,wz        ' check for subnormals, and get the abs in case it is
          if_a          jmp     #:exit1

:subnormal              or      manA, #1                ' adjust mantissa
                        ror     manA, #1

                        shr     manA, expA
                        mov     expA, #0                ' biased exponent = 0

:exit1                  mov     fnumA, manA             ' bits 22:0 mantissa
                        shr     fnumA, #9
                        movi    fnumA, expA             ' bits 23:30 exponent
                        shl     flagA, #31
                        or      fnumA, flagA            ' bit 31 sign            
_Pack_ret               ret


''****************  ALL THESE ARE FROM Float32A ****************''

'------------------------------------------------------------------------------
' _FMod fnumA = fnumA mod fnumB
'------------------------------------------------------------------------------

_FMod                   mov     t4, fnumA               ' save fnumA
                        mov     t5, fnumB               ' save fnumB
                        call    #_FDiv                  ' a - float(fix(a/b)) * b
                        mov     fnumB, #0
                        call    #_FTruncRound
                        call    #_FFloat
                        mov     fnumB, t5
                        call    #_FMul
                        or      fnumA, Bit31
                        mov     fnumB, t4
                        andn    fnumB, Bit31
                        call    #_FAdd
                        test    t4, Bit31 wz            ' if a < 0, set sign
          if_nz         or      fnumA, Bit31
_FMod_ret               ret

'------------------------------------------------------------------------------
' _ATan2 fnumA = atan2( fnumA, fnumB )
' y = fnumA, x = fnumB
'------------------------------------------------------------------------------

_ATan2                  call    #_Unpack2               ' OK, start with the basics
                        mov     fnumA, #0               ' clear my accumulator
                        ' which is the larger exponent?
                        sub     expA, expB
                        abs     expA, expA      wc
                        ' make the exponents equal
              if_c      shr     manA, expA
              if_nc     shr     manB, expA

                        ' correct signs based on the Quadrant
                        test    flagA, #SignFlag wc
                        test    flagB, #SignFlag wz
              if_z_eq_c neg     manA, manA
              if_nz     sumc    fnumA, CORDIC_Pi

                        ' do the CORDIC thing
                        mov     t1, #0
                        mov     t2, #25                 ' 20 gets you the same error range as the original, 29 is best, 25 is a nice compromise
                        movs    :load_C_table, #CORDIC_Angles

:CORDIC                 ' do the actual CORDIC thing
                        mov     t3, manA        wc      ' mark whether our Y component is negative or not
                        sar     t3, t1
                        mov     t4, manB
                        sar     t4, t1
                        sumc    manB, t3                ' C determines the direction of the rotation
                        sumnc   manA, t4        wz      ' (be ready to short-circuit as soon as the Y component is 0)
:load_C_table           sumc    fnumA, 0-0
                        ' update all my counters (including the code ones)
                        add     :load_C_table, #1
                        add     t1, #1
                        ' go back for more?
                        djnz    t2, #:CORDIC

                        ' convert to a float
                        mov     expA, #1
                        abs     manA, fnumA     wc
                        muxc    flagA, #SignFlag
                        call    #_Pack

_ATan2_ret              ret

CORDIC_Pi               long    $3243f6a8       ' Pi in 30 bits (otherwise we can overflow)
' The CORDIC angle table...binary 30-bit representation of atan(2^-i)
CORDIC_Angles           long $c90fdaa, $76b19c1, $3eb6ebf, $1fd5ba9, $ffaadd
                        long $7ff556, $3ffeaa, $1fffd5, $ffffa, $7ffff
                        long $3ffff, $20000, $10000, $8000, $4000
                        long $2000, $1000, $800, $400, $200
                        long $100, $80, $40, $20, $10
                        'long $8, $4, $2, $1


'------------------------------------------------------------------------------
' _ASin   fnumA = asin(fnumA)
' asin( x ) = atan2( x, sqrt( 1 - x*x ) )
' acos( x ) = atan2( sqrt( 1 - x*x ), x )
'------------------------------------------------------------------------------

_ASinCos                ' grab a copy of both operands
                        mov     t5, fnumA
                        mov     t6, fnumB
                        ' square fnumA
                        mov     fnumB, fnumA
                        call    #_FMul
                        mov     fnumB, fnumA
                        mov     fnumA, One
                        call    #_FSub
                        '       quick error check
                        test    fnumA, bit31    wc
              if_c      mov     fnumA, NaN
              if_c      jmp     #_ASinCos_ret
                        ' carry on
                        call    #_FSqr
                        ' check if this is sine or cosine (determines which goes into fnumA and fnumB)
                        mov     t6, t6          wz
              if_z      mov     fnumB, t5
              if_nz     mov     fnumB, fnumA
              if_nz     mov     fnumA, t5
                        call    #_ATan2
_ASinCos_ret            ret

'------------------------------------------------------------------------------
' _Floor fnumA = floor(fnumA)
' _Ceil fnumA = ceil(fnumA)
'------------------------------------------------------------------------------

_Ceil                   mov     t6, #1                  ' set adjustment value
                        jmp     #floor2
                        
_Floor                  neg     t6, #1                  ' set adjustment value

floor2                  call    #_Unpack                ' unpack variable
          if_c          jmp     #_Floor_ret             ' check for NaN
                        cmps     expA, #23 wc, wz       ' check for no fraction
          if_nc         jmp     #_Floor_ret              

                        mov     t4, fnumA               ' get integer value
                        mov     fnumB, #0
                        call    #_FTruncRound
                        mov     t5, fnumA
                        xor     fnumA, t6
                        test    fnumA, Bit31 wz
          if_nz         jmp     #:exit

                        mov     fnumA, t4               ' get fraction  
                        call    #_Frac

                        or      fnumA, fnumA wz
          if_nz         add     t5, t6                  ' if non-zero, then adjust

:exit                   mov     fnumA, t5               ' convert integer to float 
                        call    #_FFloat                '}                
_Ceil_ret
_Floor_ret              ret


'-------------------- constant values -----------------------------------------

One                     long    1.0
NaN                     long    $7FFF_FFFF
Minus23                 long    -23
Mask23                  long    $007F_FFFF
Mask29                  long    $1FFF_FFFF
Bit29                   long    $2000_0000
Bit30                   long    $4000_0000
Bit31                   long    $8000_0000
LogTable                long    $C000
ALogTable               long    $D000
SineTable               long    $E000

'-------------------- initialized variables -----------------------------------

ret_ptr_ptr             long    4               ' init to 4 so I can add to par in 1 command

'-------------------- local variables -----------------------------------------

ret_ptr                 res     1
t2                      res     1
t3                      res     1
t4                      res     1
t5                      res     1
t6                      res     1
t7                      res     1
t8                      res     1

fnumA                   res     1               ' floating point A value
flagA                   res     1
expA                    res     1
manA                    res     1

fnumB                   res     1               ' floating point B value
flagB                   res     1
expB                    res     1
manB                    res     1

fit $1F0 ' A cog has 496 longs available, the last 16 (to make it up to 512) are register shadows.

' command dispatch table: compiled along with Cog RAM, but does not neet to fit in it.
cmdFAdd                 call    #_FAdd
cmdFSub                 call    #_FSub
cmdFMul                 call    #_FMul
cmdFDiv                 call    #_FDiv
cmdFFloat               call    #_FFloat
cmdFTruncRound          call    #_FTruncRound
cmdUintTrunc            call    #_UintTrunc
cmdFSqr                 call    #_FSqr
cmdFCmp                 call    #_FCmp
cmdFSin                 call    #_Sin
cmdFCos                 call    #_Cos
cmdFTan                 call    #_Tan
cmdFLog2                call    #_Log2
cmdFExp2                call    #_Exp2
cmdFPow                 call    #_Pow
cmdFFrac                call    #_Frac
' new stuff, from Float32Full
cmdFMod                 call    #_FMod
cmdASinCos              call    #_ASinCos
cmdATan2                call    #_ATan2
cmdCeil                 call    #_Ceil
cmdFloor                call    #_Floor

{{
+------------------------------------------------------------------------------------------------------------------------------+
|                                                   TERMS OF USE: MIT License                                                  |                                                            
+------------------------------------------------------------------------------------------------------------------------------+
|Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    | 
|files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    |
|modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software|
|is furnished to do so, subject to the following conditions:                                                                   |
|                                                                                                                              |
|The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.|
|                                                                                                                              |
|THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          |
|WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         |
|COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   |
|ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         |
+------------------------------------------------------------------------------------------------------------------------------+
}}
