{{
  PropTCP Sockets - FullDuplexSerial API Layer
  --------------------------------------------
  
  Copyright (c) 2006-2009 Harrison Pham <harrison@harrisonpham.com>
   
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
   
  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.
   
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  The latest version of this software can be obtained from
  http://hdpham.com/PropTCP and http://obex.parallax.com/
}}

'' NOTICE:  All buffer sizes must be a power of 2!

OBJ
  tcp : "driver_socket"
  
VAR
  long handle
  word listenport
  byte listening

  long ptrrxbuff, ptrtxbuff
  word rxlen, txlen

PUB start(cs, sck, si, so, int, xtalout, macptr, ipconfigptr)

  tcp.start(cs, sck, si, so, int, xtalout, macptr, ipconfigptr)

PUB stop

  tcp.stop

PUB connect(ipaddr, remoteport, _ptrrxbuff, _rxlen, _ptrtxbuff, _txlen)

  {if tcp.isValidHandle(handle)
    close}

  listening := false  
  handle := -1
  handle := tcp.connect(ipaddr, remoteport, _ptrrxbuff, _rxlen, _ptrtxbuff, _txlen)

  return handle 

PUB listen(port, _ptrrxbuff, _rxlen, _ptrtxbuff, _txlen)

  {if tcp.isValidHandle(handle)
    close}

  listenport := port
  ptrrxbuff := _ptrrxbuff
  rxlen := _rxlen
  ptrtxbuff := _ptrtxbuff
  txlen := _txlen
  listening := true
  handle := -1
  handle := tcp.listen(listenport, ptrrxbuff, rxlen, ptrtxbuff, txlen)

  return handle

PUB relisten
  if listening
    ifnot tcp.isValidHandle(handle)
      listen(listenport, ptrrxbuff, rxlen, ptrtxbuff, txlen)

PUB isConnected

  return tcp.isConnected(handle)

PUB rxcount

  return tcp.getReceiveBufferCount(handle)

PUB resetBuffers

  tcp.resetBuffers(handle)

PUB waitConnectTimeout(ms) : connected | t

  t := cnt
  repeat until (connected := isConnected) or (((cnt - t) / (clkfreq / 1000)) > ms)

PUB close

  tcp.close(handle)
  handle := -1

PUB rxflush

  repeat while rxcheck => 0

PUB rxcheck : rxbyte

  {if listening
    relisten
    rxbyte := tcp.readByteNonBlocking(handle)
  else}
    rxbyte := tcp.readByteNonBlocking(handle)
    if (not tcp.isConnected(handle)) and (rxbyte == -1)
      abort tcp#ERRSOCKETCLOSED

PUB rxtime(ms) : rxbyte | t

  t := cnt
  repeat until (rxbyte := rxcheck) => 0 or (cnt - t) / (clkfreq / 1000) > ms

PUB rx : rxbyte

  repeat while (rxbyte := rxcheck) < 0

PUB rxdatatime(ptr, maxlen, ms) : len | t

  t := cnt
  repeat until (len := tcp.readDataNonBlocking(handle, ptr, maxlen)) => 0 or (cnt - t) / (clkfreq / 1000) > ms

PUB rxdata(ptr, maxlen)

  return tcp.readData(handle, ptr, maxlen)

PUB txflush

  tcp.flush(handle)

PUB txcheck(txbyte)

  {if listening
    relisten}

  ifnot tcp.isConnected(handle)
    abort tcp#ERRSOCKETCLOSED

  return tcp.writeByteNonBlocking(handle, txbyte)

PUB tx(txbyte)

  repeat while txcheck(txbyte) < 0

PUB txdata(ptr, len)

  {if listening
    relisten}

  tcp.writeData(handle, ptr, len)

PUB str(stringptr)                

  txdata(stringptr, strsize(stringptr))    

PUB dec(value) | i

'' Print a decimal number

  if value < 0
    -value
    tx("-")

  i := 1_000_000_000

  repeat 10
    if value => i
      tx(value / i + "0")
      value //= i
      result~~
    elseif result or i == 1
      tx("0")
    i /= 10


PUB hex(value, digits)

'' Print a hexadecimal number

  value <<= (8 - digits) << 2
  repeat digits
    tx(lookupz((value <-= 4) & $F : "0".."9", "A".."F"))


PUB bin(value, digits)

'' Print a binary number

  value <<= 32 - digits
  repeat digits
    tx((value <-= 1) & 1 + "0")