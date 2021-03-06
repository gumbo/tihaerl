{{                                              

 etherCog-buffer-queue
──────────────────────────────────────────────────────────────────

This is a utility object which manages a FIFO buffer of allocatable
buffer descriptors. Buffer queues can be initialized from a fixed
chunk of hub memory, or from an initial linked list of buffer
descriptors.

┌───────────────────────────────────┐
│ Copyright (c) 2008 Micah Dowty    │               
│ See end of file for terms of use. │
└───────────────────────────────────┘

}}

CON
  BD_SIZE = 2                 ' Buffer descriptor size, in longs
  BD_BYTES = BD_SIZE * 4      ' Buffer descriptor size, in bytes
  BUF_BYTESWAP = 1            ' Flag for pointer to byte-swapped buffer
  
VAR
  word  head, tail

PUB empty
  '' Empty the queue.
  head~

PUB initFromList(l)
  '' Initialize the buffer queue from an existing linked list
  '' of buffer descriptors. The provided linked list must not
  '' be circular.

  empty
  putN(l)
  
PUB initFromMem(numBuffers, bufferSize, bufferMem, bdMem)
  '' Initialize the buffer queue to use a static chunk of hub
  '' memory, preallocated in your object's VAR or DAT section.
  ''
  '' bufferSize, bufferMem, and bdMem must all be multiples
  '' of 4 bytes. bufferMem must point to (numBuffers * bufferSize)
  '' bytes, and bdMem points to (numBuffers * BD_SIZE) longs.
  ''
  '' The resulting buffer list will start at the beginning of
  '' bufferMem and increase linearly to the end of the buffer.
  ''
  '' The low bits of packetBuf may contain optional flags, like
  '' BUF_BYTESWAP. This flag enables automatic endian conversion
  '' in the driver cog, and increases transfer speeds slightly.

  empty
  repeat numBuffers
    LONG[bdMem]~
    LONG[bdMem + 4] := (bufferSize << 16) | bufferMem
    put(bdMem)

    bufferMem += bufferSize
    bdMem += BD_BYTES

PUB initFromMemSimple(bufStart, bufEnd, packetSize) | numPackets, bdEnd
  '' Initialize the buffer queue by automatically subdividing
  '' the provided buffer into chunks of 'packetSize' bytes.
  '' bufStart and packetSize must be multiples of 4.
  '' 'bufStart' points to the beginning of the buffer,
  '' 'bufEnd' points just after the end of the buffer.
  
  numPackets := (bufEnd - bufStart) / (packetSize + BD_BYTES)
  initFromMem(numPackets, packetSize, bufStart + numPackets * BD_BYTES, bufStart) 
              
PUB put(bd)
  '' Append a single buffer descriptor. The descriptor's "next"
  '' pointer is ignored, and always overwritten.

  WORD[bd]~
  if head
    WORD[tail] := bd
    tail := bd
  else
    head := tail := bd

PUB putN(l) | nextPtr
  '' Append any number of buffer descriptors. 'l' points to
  '' a linked list of buffer descriptors. The list must not be
  '' circular.

  if head
    WORD[tail] := l
  else
    head := tail := l

  repeat while nextPtr := WORD[tail]
    tail := nextPtr

PUB get : bd
  '' Remove a single buffer descriptor from the head of the
  '' queue, and return it. If no buffers are available, returns zero.
  '' The returned buffer's "next" pointer will be zero.

  if head
    head := WORD[bd := head]
  else
    bd~
  WORD[bd]~

PUB getN(n) : l | t
  '' Remove any number of buffer descriptors from the head of
  '' the queue, and return them as a linked list. If we run
  '' out of buffers, returns a short list. This resets the
  '' "next" pointers of all received packets.

  if n > 0 and l := head
    repeat n
      head := WORD[t := head]
    WORD[t] := 0
  else
    l~

PUB getAll : l
  '' Remove all buffers from the queue, and return them in a single list.

  l := head
  head~

PUB count : n | nextPtr
  '' Return the number of items in the queue.

  nextPtr := head
  n~
  repeat while nextPtr
    n++
    nextPtr := WORD[nextPtr]

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