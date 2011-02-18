''
'' Simple test program for the etherCog object.
''
'' Micah Dowty <micah@navi.cx>
''

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  BUFFER_SIZE = 1472
  NUM_BUFFERS = 8
  
OBJ
  netDrv  : "etherCog-enc28j60"
  sock    : "etherCog-udp-socket"
  bufq    : "etherCog-buffer-queue"
  
  debug   : "FullDuplexSerial"

VAR
  long  bufMem[BUFFER_SIZE * NUM_BUFFERS / 4]
  long  bufBD[bufq#BD_SIZE * NUM_BUFFERS]
  
PUB main | txBuf, rxBuf

'  debug.start(12)
  debug.start(31, 30, 0, 115200)

'csPin, sckPin, siPin, soPin
{ ETH_CS  = 21
  ETH_SCK = 20
  ETH_SI  = 19
  ETH_SO  = 18
  ETH_INT = 17
                   }

  netDrv.start(21, 20, 19, 18)

  netDrv.link(sock.init(4004))

' bufq.initFromList(netDrv.getRecycledBuffers(16))  
  bufq.initFromMem(NUM_BUFFERS, BUFFER_SIZE, @bufMem, @bufBD)

  sock.rxQueueInit(bufq.getN(NUM_BUFFERS-1))

  repeat while sock.isBound <> true

  debug.str(string("got socket"))

  txBuf := bufq.getN(1)

  bytemove(WORD[txBuf+2], string("start"), 5)
  WORD[txBuf+1] := 5

  debug.str(string("sent start"))

  sock.txQueuePut(txBuf)

  repeat while sock.txQueueGet == 0

  debug.str(string("sent"))

  repeat
    if rxBuf := sock.rxQueueGet
       txBuf := sock.txQueueGet
       bytemove(WORD[txBuf+2], WORD[rxBuf+2], WORD[rxBuf+1])
       sock.txQueuePut(txBuf)
       sock.rxQueuePut(rxBuf)
       debug.str(WORD[txBuf+2])
