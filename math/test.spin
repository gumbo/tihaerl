OBJ
  m : "DynamicMathLib"
PUB main | xDist, yDist, zDist, xTime, pathLength
  m.lock
  xDist := m.FFloat(10)
  yDist := m.FFloat(10)
  zDist := m.FFloat(0)
  pathLength := m.FSqr(m.FAdd(m.FAdd(m.FMul(xDist, xDist), m.FMul(yDist, yDist)), m.FMul(zDist, zDist)))     
  xTime := m.FRound(m.FDiv(m.FMul(clkFreq, pathLength), m.FMul(xRate, xDist)))

  len := m.FRound(pathLength)
  len2 := xTime
    

DAT
m1 LONG $FEFDFCFB
len LONG $0
len2 LONG $0
len3 long $0
m2 LONG $FEFDFCFB
t LONG $0
tt LONG $0
m3 LONG $FEFDFCFB