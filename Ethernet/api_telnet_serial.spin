{{
  PropTCP Sockets - FullDuplexSerial API Layer
  --------------------------------------------
  
  Copyright (C) 2006-2009 Harrison Pham <harrison@harrisonpham.com>

  This file is part of PropTCP.
   
  PropTCP is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3 of the License, or
  (at your option) any later version.
   
  PropTCP is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
   
  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
}}

OBJ
  tcp : "driver_socket"
  
VAR
  long handle
  word listenport
  byte listening

PUB start(cs, sck, si, so, int, xtalout, macptr, ipconfigptr)

  tcp.start(cs, sck, si, so, int, xtalout, macptr, ipconfigptr)

PUB stop

  tcp.stop

PUB connect(ipaddr, remoteport)

  listening := false
  handle := tcp.connect(ipaddr, remoteport)

  return handle 

PUB listen(port)

  listenport := port
  listening := true
  handle := tcp.listen(listenport)

  return handle

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

PUB rxflush

  repeat while rxcheck => 0

PUB rxcheck : rxbyte

  if listening
    ifnot tcp.isValidHandle(handle)
      listen(listenport)
    rxbyte := tcp.readByteNonBlocking(handle)
  else
    rxbyte := tcp.readByteNonBlocking(handle)
    if (not tcp.isConnected(handle)) and (rxbyte == -1)
      abort tcp#ERRSOCKETCLOSED

  'return tcp.readByteNonBlocking(handle)

PUB rxtime(ms) : rxbyte | t

  t := cnt
  repeat until (rxbyte := rxcheck) => 0 or (cnt - t) / (clkfreq / 1000) > ms

PUB rx : rxbyte

  repeat while (rxbyte := rxcheck) < 0

PUB rxdatatime(ptr, maxlen, ms) : len | t

  t := cnt
  repeat until (len := tcp.readData(handle, ptr, maxlen)) => 0 or (cnt - t) / (clkfreq / 1000) > ms

PUB rxdata(ptr, maxlen)

  return tcp.readData(handle, ptr, maxlen)

PUB txflush

  tcp.flush(handle)

PUB txcheck(txbyte)

  if listening
    ifnot tcp.isValidHandle(handle)
      listen(listenport)
  'else
  '  ifnot tcp.isConnected(handle)
  '    abort tcp#ERRSOCKETCLOSED

  ifnot tcp.isConnected(handle)
    abort tcp#ERRSOCKETCLOSED

  return tcp.writeByteNonBlocking(handle, txbyte)

PUB tx(txbyte)

  repeat while txcheck(txbyte) < 0

PUB txdata(ptr, len)

  if listening
    ifnot tcp.isValidHandle(handle)
      listen(listenport)

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