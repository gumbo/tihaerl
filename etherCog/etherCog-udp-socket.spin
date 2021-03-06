{{                                              

 etherCog-udp-socket
──────────────────────────────────────────────────────────────────

This is a UDP socket object, for use with etherCog. Applications
should create one instance of this object for every UDP socket they
want to use simultaneously.

This module is just a Spin API for convenience. The network stack
implementation behind this socket is contained entirely in the
driver cog. If you want to use a socket from assembly language,
you can use this file as a reference for how to perform various
socket operations using the Socket Descriptor structure.

For a full description of Socket Descriptors and Buffer Descriptors,
see the documentation comments in the etherCog driver source.

┌───────────────────────────────────┐
│ Copyright (c) 2008 Micah Dowty    │               
│ See end of file for terms of use. │
└───────────────────────────────────┘

}}

VAR
  ' Socket Descriptor structure.
  '
  ' See the etherCog driver's documentation.
  ' Note that we must declare this entirely using
  ' longs, not a mix of longs and words, because Spin
  ' always groups VARs by size before allocating them.
  
  long  sd_next
  long  sd_peer_ip
  long  sd_peer_port
  long  sd_rx
  long  sd_tx

  ' Internal variables for receive/transmit state
  
  word  rx_count      ' Last known sd_rx packet count
  word  rx_head       ' Oldest packet still waiting on recieve
  word  rx_tail       ' Most recently submitted receive packet
  
  word  tx_count      ' Last known sd_tx packet count
  word  tx_head       ' Oldest packet still waiting on transmit
  word  tx_tail       ' Most recently submitted transmit packet

CON
  X_BIT = 2           ' Transmit enable bit, in sd_next
  
PUB init(port) : p
  '' Initialize the UDP port. For convenience, we also return
  '' the port's Socket Descriptor pointer (see 'ptr' below).
  '' This pointer must be linked into the driver cog, or linked
  '' to another socket which is in turn linked to the driver cog.

  p := @sd_next
  sd_next := port << 16
  longfill(@sd_peer_ip, 0, 4)
  wordfill(@rx_count, 0, 6)
  
PUB ptr : p
  '' Return a pointer to our Socket Descriptor. This is the
  '' value passed to the driver's link() function.

  p := @sd_next

PUB link(nextSocket) : p
  '' Link this socket to the provided 'nextSocket' socket descriptopr.
  '' For convenience, this also returns a pointer to our own socket
  '' descriptor.
  ''
  '' This function can be used for building linked lists of socket
  '' descriptors, making it easier to develop objects which use
  '' many sockets. A single high-level object, like a web server,
  '' may link together several sockets into a single socket list
  '' that is passed back to the main program. This way even the web
  '' server does not need any direct coupling to the etherCog driver.

  ' Note that this clears the T flag. That's fine, since
  ' we're a UDP socket. A TCP socket would need to preserve this bit.

  WORD[@sd_next] := nextSocket
  p := @sd_next

PUB bind(ip, port)
  '' Bind this socket to a single IP address, specified as
  '' a single 32-bit long, and a single port. After binding,
  '' all transmitted packets are directed to this IP and port,
  '' and we can only receive packets from the same IP and port.
  ''
  '' A socket may only be bound if it has not yet been linked
  '' to the driver cog, or if it is already bound to another
  '' IP address. Unbound sockets may not be bound, because
  '' it causes a race condition: The driver cog may bind an
  '' unbound socket at any time, because it received a packet.

  sd_peer_port~                 ' Disable packet reception without unbinding
  sd_peer_ip   := ip            ' Atomically re-bind
  sd_peer_port := port << 16    ' Re-enable on new port

PUB unbind
  '' Unbind this socket. Unbound sockets cannot transmit, and they
  '' can receive from any peer. Sockets start out in the unbound
  '' state. You can only unbind a socket if it is bound.

  sd_peer_port~
  sd_peer_ip~

PUB peerAddr : p
  '' Get this socket's peer IP, as a single 32-bit long.

  p := sd_peer_ip

PUB peerPort : p
  '' Get this socket's peer port.

  p := sd_peer_port >> 16

PUB isBound : bool
  '' Is this socket bound to a peer? Sockets start out unbound.
  '' They may be explicitly bound/unbound by their owner, or an
  '' unbound socket may be implicitly bound when a packet is
  '' first received on that socket.

  bool := sd_peer_ip <> 0 

PUB localPort : p
  '' Get this socket's local port. Usually this is the same
  '' value passed to init(), but if this socket was initialized
  '' with no port (zero) and bound to a driver cog, this function
  '' will tell you which ephemeral port number was assigned to
  '' this socket.

  p := sd_next >> 16

PUB rxQueueInit(l)
  '' Start receiving packets using a queue of buffer descriptors.
  '' This chooses one flavor of data reception. These rxQueue functions
  '' cannot be mixed with the other rx* functions.
  ''                          
  '' The buffer list must contain at least two buffers. rxQueue cannot
  '' function properly with only a single packet buffer, since there would
  '' be no way for rxQueuePut() to append a new buffer without creating
  '' an infinite buffer loop.
  ''
  '' To check for received packets after rxQueueInit, call rxQueueGet.
  '' To (re)submit new packets to the queue, call rxQueuePut.

  rx_count~
  sd_rx := rx_head := l

  rx_tail := l  
  repeat while l := WORD[l]
    rx_tail := l

PUB rxQueueGet : bd | local_sd_rx
  '' Get a single buffer descriptor from the receive queue.
  '' If a packet has been received, this dequeues it and returns
  '' its buffer descriptor. If no packets have been received,
  '' returns zero.
  ''
  '' One limitation of an rxQueue as compared to other receive
  '' mechanisms is that at least one packet must remain pending
  '' at all times. In fact, this final packet may be received by
  '' the driver cog, but we may not be able to return it because
  '' its "next" pointer is still needed in order to enqueue new
  '' receive packets. This means that if you experience a receive
  '' underrun (the driver cog runs out of rx buffers) it may cause
  '' this final packet to get "stuck" until another packet is
  '' received.

  ' Atomically capture sd_rx into a local cache.
  local_sd_rx := sd_rx

  ' If the receive count has been incremented, no packets were
  ' received. If the sd_rx pointer matches rx_head, we've received
  ' a packet but we can't return it until the driver cog is fully
  ' done with it.
  '
  ' When we dequeue a packet, it may be in one of two states as
  ' far as the driver cog is concerned:
  '
  '   1. The packet receive is completely finished, and the driver
  '      cog has moved on to the next buffer descriptor.
  '
  '   2. The receive is completely finished, but there is no next
  '      buffer descriptor yet. In this case, the driver has to
  '      keep sd_rx pointing at the completed packet, but with
  '      the N (next) bit set.
  '
  ' So, we know that the driver cog starts using this packet before
  ' incrementing the packet count, and we know it finishes with it
  ' before writing the sd_rx long. We need to make two tests:
  '
  '   A. Has the packet count been incremented?
  '   B. Is sd_rx not pointing at this packet?
  '
  ' If both tests pass, we can return the rx_head buffer.

  if rx_count <> local_sd_rx >> 16 and (rx_head ^ local_sd_rx) & $FFFC
    rx_count++
    rx_head := WORD[bd := rx_head]
  else
    bd~

PUB rxQueuePut(bd)
  '' Submit or re-submit a single buffer descriptor to the end of the
  '' receive queue. After packets have been recieved on these buffers,
  '' they will become available via rxQueueGet. The rxQueue must have
  '' first been initialized using rxQueueInit.
  ''
  '' The BD's "next" pointer will be ignored, and replaced with zero.

  WORD[bd]~
  WORD[rx_tail] := bd
  rx_tail := bd

PUB rxQueuePutN(l)
  '' Like rxQueuePut(), but submit an entire linked list of buffer
  '' descriptors to the end of the receive queue.

  WORD[rx_tail] := l
  rx_tail := l
  repeat while l := WORD[l]
    rx_tail := l

PUB rxRingInit(l)
  '' Start receiving packets using a continuous ring of buffer
  '' descriptors. This is similar to rxQueue in that we receive
  '' packets into a linked list of Buffer Descriptors, however
  '' unlike rxQueue the driver cog will never wait for you to
  '' manually get/put packets. The driver will continuously write
  '' to this ring of buffers, and if your cog falls behind, the
  '' driver will just overwrite the oldest data.
  ''
  '' rxRing is a good choice for receiving data which is very
  '' high-bandwidth or time-critical. It's also good if you're
  '' processing the received data in assembly language, since you'll
  '' be able to keep up with the full rate that the driver cog
  '' can write at.
  ''
  '' The API is similar to rxQueue: The ring must be initialized
  '' using a linked list of buffer descriptors. During initialization,
  '' we link the buffers into a circle.

  rxQueueInit(l)
  WORD[rx_tail] := rx_head

PUB rxRingGetCount : c
  '' Unlike rxQueue, and rxRing will receive asynchronously without
  '' any interaction with other cogs. The only input you get directly
  '' from the socket in this case is some indication of how much data
  '' has been received.
  ''
  '' This function lets you check how many packets have been received
  '' by this socket, in total, modulo 2^16. The caller can use this
  '' information to calculate a packet reception rate, a pointer to the
  '' most recent data, or whatever other metric is necessary.
  ''
  '' This value increments as soon as any packet for this socket is
  '' fully received and stored by the driver cog.

  c := sd_rx >> 16

PUB txStop
  '' Stop transmitting as soon as possible. There is no guarantee
  '' that we'll be done transmitting by the time this function returns,
  '' since all transmissions are asynchronous. There is also no guarantee
  '' of exactly how many packets will be transmitted, if txStop is called
  '' while packets are enqueued for transmit.
  ''
  '' After calling txStop, the driver will stop visiting this socket looking
  '' for transmittable data. If you know the socket is finished transmitting
  '' and you don't plan on sending new data right away, this function can be
  '' used to increase the efficiency of the driver cog's socket polling.

  sd_next &= !X_BIT
  sd_tx~
  
PUB txQueuePut(bd)
  '' Enqueue a single buffer for asynchronous transmission. If transmission
  '' has not begun yet, we begin it with this buffer. There is no txQueueInit(),
  '' since it wouldn't make sense to pre-load the transmit queue with packets
  '' at initialization time.
  ''
  '' The data in 'bd' is eventually transmitted, and the buffer will be
  '' available for recycling via txQueueGetAll().

  WORD[bd]~

  if sd_tx
    ' Link to an existing transmit list
    WORD[tx_tail] := bd
    tx_tail := bd
  else
    ' First-time transmit initialization, analogous to rxQueueInit().
    tx_count~
    sd_tx := tx_head := tx_tail := bd
    sd_next |= X_BIT 


PUB txQueueGet : bd | local_sd_tx
  '' Get a single buffer descriptor from the transmit queue.
  '' If we've finished using any buffers, returns a BD pointer.
  '' If no buffers are free, returns zero.

  ' See rxQueueGet for details on why these conditions are the way they are.
  ' We need to make sure that a packet has been received, and that the
  ' buffer is not still in use by the driver cog.

  local_sd_tx := sd_tx

  if tx_count <> local_sd_tx >> 16 and (tx_head ^ local_sd_tx) & $FFFC
    tx_count++
    tx_head := WORD[bd := tx_head]
  else
    bd~
  
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