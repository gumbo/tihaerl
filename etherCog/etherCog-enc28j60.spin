{{                                              

 etherCog-enc28j60
──────────────────────────────────────────────────────────────────

I. Introduction

 This is a fast single-cog driver for the ENC28J60, an easy to
 use SPI-attached 10baseT chip from Microchip. It implements
 the chip's SPI protocol, as well as ARP, IP, ICMP, UDP and TCP.

 The etherCog is designed to be a self-contained networking stack,
 usable from either Spin or Assembly cogs. Multiple cogs or objects
 can use etherCog simultaneously, because all communication is
 performed via individual isolated "socket" objects.

 This file provides a driver object that asynchronously processes
 the reception and transmission of packets via low-level socket
 objects. The etherCog-tcp-socket and etherCog-udp-socket objects
 are implementations of the TCP and UDP protocols, respectively,
 using these low-level socket objects.

II. Sockets

 Just like a traditional TCP/IP socket, our low-level sockets are
 bidirectional entities that connect two endpoints. Our sockets
 have a local and a peer address, and a collection of receive
 and transmit buffers.

 The local address of a socket is our local IP and MAC address,
 combined with the socket's local port. Every socket must have
 a local port. In the case of a server-style socket, this port is
 something you'll assign manually. In a client-style socket, the
 port can be chosen automatically.

 The peer address consists of a MAC address, IP address, and port.
 The IP address and port are stored explicitly in the Socket
 Descriptor, but the MAC address is retrieved via the driver cog's
 ARP cache as needed.
 
 Our low-level sockets can either be "bound" or "unbound". A bound
 socket can transmit, and it can accept incoming packets only from
 a single specified peer address. An unbound socket cannot transmit,
 but it can accept incoming packets from any peer address. As soon
 as a packet arrives, the peer address of that packet is stored in
 the socket and the socket becomes bound.

 This means you can implement a server by creating N sockets, where
 N is the maximum number of simultaneous connections supported.

 Sockets are represented by a "Socket descriptor", a simple data
 structure in hub memory. Socket descriptors have a well-defined
 format. They are generally located in memory owned by other
 objects, like etherCog-udp-socket. These socket descriptors are
 referenced by a global linked list that the driver cog uses.
 
         Socket Descriptor
         ┌────────────────────┬────────────────┬─┬─┐
  Long 0 │ Local port [31:15] │ Next [15:2]    │X│T│
         ├────────────────────┴────────────────┴─┴─┤
       1 │ Peer IP                                 │ 
         ├────────────────────┬────────────────────┤
       2 │ Peer port [15:0]   │ (Reserved)         │ 
         ├────────────────────┼──────────────────┬─┤
       3 │ RX Count [31:16]   │ RX Ptr [15:1]    │N│
         ├────────────────────┼──────────────────┼─┤
       4 │ TX Count [31:16]   │ TX Ptr [15:1]    │N│
         └────────────────────┴──────────────────┴─┘

    Reserved bits:
      Must be initialized to zero.
         
    Next:
      Hub address of the next socket in the global linked list.

      The 'next' pointer must remain constant after a socket is added
      to the driver cog's linked list. There is no safe way to remove
      sockets from the list- they are intended to be static resources.

    X bit:
      This bit enables transmit for this socket. If X=1,
      the driver cog will check the TX field for buffers to transmit.
      If X=0, the driver will save time by skipping this socket entirely
      when looking for packets to transmit.
      
    T bit:
      If T=1, this is a TCP socket.
      If T=0, this is a UDP socket.

      This bit remains constant for the lifetime of the socket.
      It may not be changed after the socket is linked into the
      driver cog's list.

    Local port:
      The local TCP/UDP port number for this socket. Once a socket
      is visible by the driver cog, it must have a nonzero local
      port. If a socket has a local port of zero, we assign it an
      arbitrary port just before adding it to the linked list.

      This socket only receives packets directed at the local port,
      and this is the source port number used for any transmitted
      packets.

      The local port is constant for the lifetime of the socket.
      It may not be changed after the socket is linked into the
      driver cog's list.

    Peer port:
      The TCP/UDP port of our peer, if this socket is bound.
      if the socket is unbound, this field is ignored.

      If the socket is bound, the peer port may be modified by
      the socket owner in order to re-bind the socket. If the
      socket is unbound, the peer port may be modified by the
      etherCog driver when a packet is received.

    Peer IP:
      The 32-bit packed IP address of our peer, if the socket is
      bound. An unbound socket is defined as a socket in which the
      peer IP is zero.

      When the socket is bound (peer IP nonzero) the socket may
      be unbound or re-bound by the socket owner by writing to
      this long. When the socket is unbound, the driver cog may
      bind it at any time when a packet is received. Therefore,
      the socket owner must not write to the Peer IP on an
      unbound socket. An unbound socket may only be bound by the
      driver cog.

    RX Count:
      Number of packets received. Incremented by the driver cog
      every time a packet is written to a buffer descriptor. The
      increment occurs simultaneously with the RX Pointer update.

    RX Pointer:
      Hub address of the next Buffer Descriptor to write incoming
      packets into. If the RX Pointer is zero, this socket cannot
      receive packets. If this socket receives a packet, no other
      sockets may receive it. If the RX Pointer is zero, we give
      other sockets a chance to receive this packet. If no matching
      socket can receive it, the packet is dropped.
    
    TX Count:
      Number of packets transmitted. Incremented by the driver cog
      every time a packet is read from a buffer descriptor. The
      increment occurs simultaneously with the TX Pointer update.

    TX Pointer:
      Hub address of the next Buffer Descriptor to transmit. If
      the TX Pointer is zero, this socket has no data waiting to
      be transmitted.

      Socket transmissions are serviced in a round-robin fashion.
      Between any two packet transmissions from this socket, every
      other socket gets an opportunity to transmit.

    N bits:
      For both the TX and RX pointers, the "N" (Next) bit may be set
      to indicate that the actual buffer descriptor is not the one
      pointed to directly by TX/RX, but it's the one pointed to by
      the 'next' pointer of the one pointed by TX/RX. In effect, it
      adds a single extra level of indirection.

      This bit will be set automatically any time the driver cog
      reaches the end of a TX or RX queue. Instead of setting the
      TX/RX pointer to zero, the driver cog will set the N bit and
      keep the existing pointer. The driver will behave as if the
      pointer was zero, but it will automatically discover new BDs
      when they are linked to the 'next' pointer of the last
      completed buffers.

      This way, it's possible for other cogs to add more packets to the
      end of the queue without the race condition that would result
      if they wrote to the TX/RX pointer while the driver cog may
      be operating on those pointers.

      This also means that it may be necessary to explicitly clear
      the TX/RX pointers if you're about to delete a buffer or recycle
      it for another socket.
      
III. Buffers

 The RX/TX pointers point to buffer descriptors, which may form
 circular or linear queues. Each buffer descriptor has the following
 format:

         Buffer Descriptor
         ┌────────────────────┬────────────────────┐
  Long 0 │ Actual size        │ Next ptr [15:0]    │
         ├────────────────────┼──────────────────┬─┤
       1 │ Buffer size        │ Buffer [15:1]    │S│
         └────────────────────┴──────────────────┴─┘ 
           XXX: TCP header data here.

    Actual size:
      Actual number of payload bytes that this buffer received.
      This may be set by the driver cog at any time between when the
      buffer enters the receive queue and when it is completed.
      A nonzero value here does not imply that the buffer has been
      completed.

      For transmit buffers, this specifies the size of the actual
      packet to send. The actual data transmitted will be padded to
      the next 32-bit boundary, but we use the proper un-padded
      size when calculating TCP/UDP payload lengths, so our peer
      should receive the proper amount of data.

    Next pointer:
      The hub address of the next buffer in the chain. This is
      copied to the Socket Descriptor's buffer pointer after the
      buffer has been completed.

    Buffer size:
      Maximum number of bytes to read/write to the "Buffer" pointer.
      Must be a greater than zero, and must be a multiple of 4.
      Must be valid before the buffer is linked into a socket
      descriptor. Not modified by the driver cog.

      For receive buffers, this is the largest packet that we can
      receive. Larger packets will be truncated to this length.
      For transmit buffers, this value is ignored.

    Buffer:
      Points to the beginning of the buffer, with at least
      "max size" bytes available for reading/writing.

      This pointer must be aligned on a 4-byte boundary. The
      lower two bits are assumed to be zero.

    S Bit:
      This is the byte swap control bit. It selects the endianness
      of the receive/transmit buffer. If this bit is 0, bytes are
      stored in the buffer sequentially. If it's 1, each byte in
      a long is reversed. With S=1, big-endian words on the network
      are automatically translated into the Propeller's little-
      endian words, but the order of byte data (like strings) is
      also reversed.

      The etherCog transfers data more efficiently into buffers
      with S=1, because there is actually an implicit byte swap
      in our SPI engine. Buffers with S=0 require an extra swap
      step in order to undo that implicit swap.     
 
IV. License
       
 This object is an original work, except where explicitly noted.

 It is not based on Microchip's sample implementation, only the
 ENC28J60 data sheet and errata documents. Inspiration was taken
 from Harrison Pham's driver_enc28j60 object, and from fsrw's SPI
 routines- but all networking and SPI code here is original, so
 I've taken the opportunity to release this object under the MIT
 license instead of the GPL.

 The byte swapping routine in this module was written by Chip Gracey,
 for a challenge on the Propeller forums:

   http://forums.parallax.com/forums/default.aspx?f=25&m=156267

 ┌───────────────────────────────────┐
 │ Copyright (c) 2008 Micah Dowty    │               
 │ See end of file for terms of use. │
 └───────────────────────────────────┘

}}

CON
  SOCKET_DESC_LEN  = 5          ' Size of socket descriptor, in longs
  BUFFER_DESC_LEN  = 2          ' Size of buffer descriptor, in longs
  
  ' Names for the longs in a socket descriptor
  SD_NEXT       = 0             ' Next pointer and T bit
  SD_LOCAL_PORT = 2             ' Local port number
  SD_PEER_IP    = 4             ' Peer IP address  (32-bit)
  SD_PEER_PORT  = 10            ' Peer port number (16-bit)
  SD_RX         = 12            ' Receive count/pointer
  SD_TX         = 16            ' Transmit count/pointer  

  ' Socket descriptor flags
  SD_TCP        = 1
  
  ' Names for the longs in a buffer descriptor
  BD_SIZE       = 0
  BD_ADDR       = 4

OBJ
  recycleQ : "etherCog-buffer-queue"
  
VAR
  word  socket_head
  word  ephemeral_state
  byte  cog

PUB start(csPin, sckPin, siPin, soPin) : okay | handshake
  '' Initialize the ethernet driver. This resets and
  '' initializes the ENC28J60 chip, then starts a single
  '' cog for receiving and transmitting packets.
  ''
  '' This function is not re-entrant. If you have multiple
  '' etherCog objects, initialize them one-at-a-time.
  ''
  '' Sockets can be declared before or after starting the
  '' driver cog.

  ' Store raw pin numbers (for the initialization only)

  cs_pin   := csPin
  si_pin   := siPin
  so_pin   := soPin
  sck_pin  := sckPin
  
  ' Set up pin masks (for the driver cog)

  cs_mask  := |< csPin
  si_mask  := |< siPin
  so_mask  := |< soPin
  init_dira := cs_mask | si_mask | (|< sckPin)

  ' During initialization, this Spin cog owns the pins.
  ' After the driver cog itself has started, we'll disclaim
  ' ownership over them.

  outa |= cs_mask               ' Order matters. CS high first, then make it an output.
  dira |= init_dira             ' Otherwise CS will glitch low briefly.
  
  ' We use CTRA to generate the SPI clock

  init_ctra := sckPin | constant(%00100 << 26) 

  ' Send the ENC28J60 chip a software reset

  init_spi_begin
  init_spi_Write8(SPI_SRC)
  init_spi_end
  
  ' 1ms delay on reset.
  ' This is for clock stabilization and PHY init.
  ' Also see Rev B5 errata 1.

  waitcnt(cnt + clkfreq / 1000 * 50)

  ' Table-driven initialization for MAC and PHY registers.
  ' To save space in the driver cog we do this before
  ' starting it, using a slow SPI engine written in Spin. 

  init_reg_writeTable(@reg_init_table)

  ' Wire up our LMM overlay base address.
  ' (The Spin compiler isn't smart enough to resolve
  ' hub addresses at compile time.)

  lmm_base := @lmm_base_label
  pc := @init_entry

  ' The head pointer for our socket list is stored in
  ' hub memory, for simplicity. This lets us create sockets
  ' either before or after starting the driver cog.

  socket_head_ptr := @socket_head
  
  ' Start the cog, and hand off ownership over the SPI bus.
  ' We need to wait until the cog has set initial dira/outa
  ' state before we release ours, or the SPI bus will glitch.
  ' However, the cog also needs to wait until we release CS
  ' or it won't be able to send any SPI commands.
  '
  ' So, 'handshake' starts out set to -1. The cog sets it to any
  ' other value once after outa/dira are set. When we notice this,
  ' we release our ownership over the SPI bus, and set 'handshake'
  ' to zero. When the cog notices that, it continues.

  handshake~~ 
  okay := cog := 1 + cognew(@entry, @handshake)
  repeat while handshake == TRUE
  dira &= !init_dira
  outa &= !init_dira
  handshake~
  
PUB stop
  '' Immediately stop the network driver cog. Sockets will
  '' cease to make any receive/transmit progress. Connections
  '' will not be gracefully closed, the network adapter will
  '' not be reset.

  if cog > 0
    cogstop(cog - 1)
    cog~

PUB link(head) | tail, nextPtr
  '' Link one or more socket descriptors into the driver cog's global list.
  '' 'head' is a pointer to a Socket Descriptor structure in hub memory,
  '' which may optionally be linked to other socket descriptors.
  ''
  '' This function automatically assigns port numbers if any of
  '' the provided sockets have no local port, but no other
  '' initialization is performed.

  nextPtr := head
  repeat while nextPtr & $FFFC
    tail := nextPtr
    nextPtr := LONG[tail]

    if not (nextPtr >> 16)
      ' Assign the next available ephemeral port number.
      '
      ' These are the private port numbers we fill in automatically
      ' when a socket has not explicitly requested a particular port number.
      ' Since etherCog systems have a small number of sockets that are
      ' continuously reused, we can just linearly assign ephemeral ports
      ' without worrying about re-using ports or wrapping around.
      '
      ' This uses the range from $c000 to $ffff, as recommended by the IANA:
      ' http://en.wikipedia.org/wiki/Ephemeral_port
  
      LONG[tail] |= ($c000 + ephemeral_state++) << 16    

  ' Link it into our list...
  LONG[tail] |= socket_head
  socket_head := head

PUB getRecycledBuffers(packetSize) : head
  '' This function can be called once after start(), in order to reclaim unused
  '' hub memory in the form of packet buffers. This is hub memory which is used
  '' only for initialization. After calling this function, you must never call
  '' start() again.
  ''
  '' You can choose the packet size to use when subdividing the recyclable
  '' memory. The number of packets returned will be inversely proportional
  '' to the packet size you request. Beware that if you request more space than
  '' is available, we return no packets (the value zero).

  recycleQ.initFromMemSimple(@recycle_region_begin, @recycle_region_end, packetSize)
  head := recycleQ.getAll


DAT
'==============================================================================
' Low-level Initialization Code
'==============================================================================

' All hardware initialization code is optimized for space rather than speed, so
' it's written in Spin using a totally separate (and very slow) SPI engine. Init
' code runs before the main driver cog starts.
'
' This SPI engine was clocked at 24 kBps on an 80 MHz sysetm clock. No speed
' demon for sure, but it's plenty fast enough to run through the initialization
' tables once.


PRI init_spi_begin
  ' Begin an SPI command (pull CS low)
  ' This is slow enough that we definitely don't need to worry about setup/hold time.

  outa[cs_pin]~

PRI init_spi_end
  ' End an SPI command (pull CS high)
  ' This is slow enough that we definitely don't need to worry about setup/hold time.

  outa[cs_pin]~~

PRI init_spi_Write8(data)
  ' Write an 8-bit value to the SPI port, MSB first, from the 8 least significant
  ' bits of 'data'. This is a very slow implementation, used only during initialization.

  repeat 8
    outa[si_pin] := (data <<= 1) >> 8
    outa[sck_pin]~~
    outa[sck_pin]~

PRI init_reg_BankSel(reg)
  ' Select the proper bank for a register, given in the 8-bit encoded
  ' format. Since we're optimizing for space rather than speed, this
  ' always writes to ECON1, without checking to see whether we were
  ' already in the right bank. During initialization, we know ECON1
  ' is always zero (other than the bank bits).

  init_spi_begin
  init_spi_Write8(constant(SPI_WCR | (ECON1 & %11111)))
  init_spi_Write8((reg >> 5) & $03)
  init_spi_end

PRI init_reg_Write(reg, data)
  ' Write an 8-bit value to an ETH/MAC register. Automatically switches banks.

  init_reg_BankSel(reg)
  init_spi_begin
  init_spi_Write8(SPI_WCR | (reg & %11111))
  init_spi_Write8(data)
  init_spi_end

PRI init_reg_WriteTable(table) | reg
  ' Perform a list of register writes, listed as 8-bit name/value pairs
  ' in a table in hub memory. The table is terminated by a zero byte.

  repeat
    reg := BYTE[table++]
    if reg
      init_reg_Write(reg, BYTE[table++])
    else
      return

    
DAT

' Beginning of recyclable memory segments
recycle_region_begin

' Initialization-only variables used from Spin.
cs_pin        byte    0
si_pin        byte    0
so_pin        byte    0
sck_pin       byte    0 


'==============================================================================
' Driver Cog
'==============================================================================

                        '======================================================
                        ' Cog Initialization
                        '======================================================

                        ' The cog initialization consists of two main steps:
                        '
                        '   - Executing instructions, for initializing I/O and
                        '     handshaking with the cog who is running start().
                        '
                        '   - Writing unrolled SPI loops into cog memory. We
                        '     have several large unrolled loops which are necessary
                        '     for speed, but we'd rather not store them in their
                        '     entirety. They just waste hub memory.
                        '
                        ' We can accomplish both of these tasks using very little
                        ' memory, via a somewhat modified version of the Large
                        ' Memory Model concept. I call this meta-LMM. We fetch words
                        ' from main memory. Some of these words are stored at the
                        ' current write pointer and some of them are executed
                        ' immediately. This means we can interleave code and data
                        ' seamlessly, making it very natural to write code which
                        ' programmatically unrolls loops at initialization time.
                        '
                        ' The rule is that code marked with the "if_never" condition
                        ' code is stored at the current write pointer, which then
                        ' increments. Instructions with any other condition code are
                        ' run as-is. This means that we can't generate code that uses
                        ' condition codes, but this is fine for our simple SPI loops.
                        ' The other main limitation is that our VM uses the zero flag,
                        ' so the initialization code itself can only use the carry flag.
                        '
                        ' To save memory, the code memory used for the execution
                        ' engine is repurposed as temporary space after initialization
                        ' is complete. The length of the variable block here *must*
                        ' not exceed the length of the initialization code.
                        '
                        ' When initialization is done, the initialization code will
                        ' jump to the main loop.

                        org     ' Data which replaces initialization code, no more than 13 longs

r1                      res     1               ' Register name / temp
r2                      res     1               ' Register data / temp
r3                      res     1               ' High-level temporary

lmm_stack               res     2

spi_reg                 res     1
spi_write_count         res     1

rx_pktcnt               res     1               ' Number of pending packets (8-bit)
rx_next                 res     1               ' Next Packet Pointer (16-bit)

peer_MAC_high           res     1               ' High 16 bits of peer MAC
peer_MAC_low            res     1               ' Low 32 bits of peer MAC
peer_IP                 res     1               ' IP address of peer

ip_length               res     1               ' Total IP packet length
                        
                        org     ' Initialization code, 13 longs
entry
                        rdlong  :inst, pc
                        add     pc, #4
                        test    :inst, :cond_mask wz
              if_z      or      :inst, :cond_mask       ' If cond was if_never, make it if_always...
:write        if_z      mov     init_data, :inst        ' ..and write to the initialization data pointer.
              if_z      add     :write, :init_dest1     ' Advance the write pointer
              if_z      jmp     #entry
:inst                   nop                             ' Execute the immediate instruction
                        jmp     #entry
               
:cond_mask              long    %1111 << 18             ' Condition code mask
:init_dest1             long    1 << 9                  ' Value of '1' in the instruction dest field
init_dira               long    0                       ' Parameters for initialization
init_ctra               long    0


                        '======================================================
                        ' Large Memory Model VM
                        '======================================================

                        '
                        ' lmm_vm --
                        '
                        '   This is the main loop for a "Large memory model"
                        '   VM, which executes code from hub memory location 'pc'.
                        '   We use LMM for larger and less speed-critical parts
                        '   of the driver cog.
                        '
                        '   LMM code can freely call and jump into non-LMM code,
                        '   but jumping *into* LMM code requires setting the pc
                        '   manually and jumping into lmm_vm.
                        '
                        '   On entry to lmm_vm, r0 specifies an overlay-relative
                        '   address in longs (a label). This is automatically
                        '   translated into a hub-memory-relative address in bytes,
                        '   and stored in pc. We use a different register other than
                        '   pc, so lmm_vm can be called from within LMM code.
                        '              
                        ' lmm_call --
                        '
                        '   To make an LMM function call, set r0 to the destination
                        '   label, and jump here. We set up the LMM return pointer,
                        '   then re-enter the VM.
                        '
                        '   Our stack is 2 levels deep, just like the oldskool PICs ;)
                        '
                        ' lmm_ret --
                        '
                        '   Return from an LMM call.
                        '

lmm_call                mov     lmm_stack+0, lmm_stack+1
                        mov     lmm_stack+1, pc

lmm_vm                  mov     pc, r0
                        shl     pc, #2
                        add     pc, lmm_base

lmm_loop                rdlong  :inst0, pc              ' Unrolled execution loop
                        add     pc, #4
:inst0                  nop
                        rdlong  :inst1, pc
                        add     pc, #4
:inst1                  nop
                        rdlong  :inst2, pc
                        add     pc, #4
:inst2                  nop
                        jmp     #lmm_loop

lmm_ret                 mov     pc, lmm_stack+1
                        mov     lmm_stack+1, lmm_stack+0
                        jmp     #lmm_loop
                        
lmm_base                long    0                       ' LMM overlay address

                        '
                        ' Trampolines for frequently used LMM entry points.
                        ' You can jump directly to one of these trampoline labels
                        ' instead of loading the corresponding _lmm label into
                        ' r0 and calling lmm_vm.
                        '

                        '
                        ' rx_frame_finish --
                        '
                        '   Finish processing a received frame. This frees the
                        '   hardware buffer for that frame, and prepares to receive
                        '   the next one.
                        '   
rx_frame_finish         mov     r0, #rx_frame_finish_lmm
                        jmp     #lmm_vm


                        '======================================================
                        ' Main Loop
                        '======================================================

mainLoop
                        mov     r1, #EPKTCNT            ' Poll EPKTCNT (Rev B5 errata 4)
                        call    #reg_Read
                        mov     rx_pktcnt, r2 wz
              if_nz     mov     r0, #rx_frame           ' Receive any pending frames
              if_nz     jmp     #lmm_vm
mainLoop_rx_done

                        call    #tx_poll                ' Try to transmit and swap the TX double-buffer.

                        cmp     tx_back_buf, tx_back_buf_end wz
              if_nz     jmp     #mainLoop               ' TX back-buffer is busy, can't prepare a new TX frame.

                        ' If we have transmit space, fall through to socket_tx to search
                        ' for a socket that needs to transmit...


                        '======================================================
                        ' Socket Layer
                        '======================================================

                        ' This section is responsible for traversing our socket data
                        ' structures in hub memory, loading/saving the contents of
                        ' SDs (Socket Descriptors) and BDs (Buffer Descriptors), and
                        ' for actually copying data between buffers and the SPI bus.

                        '
                        ' socket_tx --
                        '
                        '   Look for a socket that's ready to transmit.
                        '   If we find one, we prepare the peer info and jump to a
                        '   protocol-specific handler. If no sockets want to transmit,
                        '   head back to the main loop.
                        '
socket_tx               cmp     socket, #0 wz           ' Start the search
              if_z      rdword  socket, socket_head_ptr wz
              if_z      jmp     #mainLoop               ' Empty socket list
                        mov     r2, socket              ' Remember first socket visited

:loop                   rdlong  r3, socket              ' Read local port, 'next' pointer, and X/T bits.
                        test    r3, #2 wz               ' Is the X bit set?
              if_nz     mov     sd_rxtx, socket         ' Point sd_rxtx at the TX status field.
              if_nz     add     sd_rxtx, #SD_TX
              if_nz     call    #socket_load_bd         ' Load our TX buffer descriptor, set Z
              if_nz     jmp     #:found                 ' If there's a buffer, we found our target socket.

                        call    #socket_next
              if_nz     jmp     #:loop
                        jmp     #mainLoop               ' Unsuccessful, no socket is listening.

:found
                        test    r3, #1 wc               ' Is the T bit set?

                        mov     r1, socket              ' Load socket's peer IP
                        add     r1, #SD_PEER_IP
                        rdlong  peer_ip, r1
                        add     r1, #(SD_PEER_PORT - SD_PEER_IP)
                        rdlong  ip_ports, r1            ' Load peer port
                        shr     ip_ports, #16           ' ..and shift it into the low word (IP dest port)
                        andn    r3, hFFFF               ' Combine with source port (Local socket port)

                        add     bd, #4                  ' Get BD size and pointer
                        rdlong  bd_szptr, bd
                        or      ip_ports, r3            ' (Re-ordered from above)
                        sub     bd, #4

                        call    #socket_next_bd         ' Advance the BD pointer
                        shr     r0, #16
                        mov     payload_len, r0         ' Save the 'actual size' as our payload length.

              if_c      mov     r0, #tx_tcp             ' Branch to a protocol handler.
              if_nc     mov     r0, #tx_udp             ' They will do some setup, then call socket_tx_finish.
                        jmp     #lmm_vm
                        
                        '
                        ' socket_next --                                            
                        '
                        '   Move to the next socket in our iteration sequence. This wraps around
                        '   when we hit the end of the linked list, but stops if we hit the first
                        '   socket visited.
                        '
                        '   On return, we should keep iterating iff Z=0.
                        '
socket_next             mov     socket, r3              ' Next socket.
                        and     socket, hFFFC wz        ' Ignore non-pointer bits, test for NULL.
              if_z      rdword  socket, socket_head_ptr ' Wrap around if necessary
                        cmp     r2, socket wz           ' At first socket yet?        
socket_next_ret         ret

                        '
                        ' socket_load_bd --
                        '
                        '   Load information about the buffer descriptor.
                        '
                        '   - The 'bd' register is loaded from the pointer in sd_rxtx. This
                        '     follows the N bit if necessary, and provides a value for 'bd'
                        '     which includes the actual current buffer pointer and packet count.
                        '
                        '     On return, the 'bd' register will be offset to point to the
                        '     "actual length" field in the upper word of the first long. For
                        '     receive, this makes it easy to write the actual payload length.
                        '     For transmit, this offset is unused. In socket_next_bd, the offset
                        '     is automatically masked off.
                        '
                        '   - The Z flag is set if and only if the buffer pointer is NULL.
                        '     IF the buffer pointer is NULL, the results below are not available.
                        '
                        '   - The bd_szptr register is set to the BD's buffer size and buffer pointer.
                        '
socket_load_bd          rdlong  bd, sd_rxtx             ' Load receive pointer and packet count
                        test    bd, #1 wz               ' Test "N" (Next) bit in BD.
              if_nz     rdword  r0, bd                  ' Follow 'next' if the N bit is set.
              if_nz     andn    bd, hFFFF               ' Replace BD's pointer (low word) with 'next'
              if_nz     or      bd, r0
                        test    bd, hFFFF wz            ' Is the real BD pointer non-NULL?

                        add     bd, #4                  ' Get BD size and pointer
              if_nz     rdlong  bd_szptr, bd
                        sub     bd, #2                  ' Point at the "actual length" field in the first word.                        
socket_load_bd_ret      ret

                        '
                        ' socket_next_bd --
                        '
                        '   Advance the 'bd' register to hold the appropriate packet count and
                        '   buffer address for the next BD.
                        '
                        '   Side-effects:
                        '      - Modifies r1.
                        '      - Loads the entire first long of the previous BD into r0.
                        '        If you need the previous BD's "actual length" field, it's
                        '        in the high 16 bits of r0.
                        '
socket_next_bd          add     bd, h10000              ' Increment packet count in high word
                        andn    bd, #3                  ' Mask off any non-pointer LSBs
                        rdlong  r0, bd                  ' Read the next pointer and "actual length".
                        mov     r1, r0
                        and     r1, hFFFF wz            ' Separate out just the 'next' pointer. Is it zero?                        
              if_z      or      bd, #1                  ' If zero, don't advance. Just set the N bit.
              if_nz     andn    bd, hFFFF               ' Mask off old BD pointer
              if_nz     or      bd, r1                  ' Insert new pointer. (If nonzero)
                                                        ' The bd long is now ready to write to the SD.                        
socket_next_bd_ret      ret

                        '
                        ' socket_rx --
                        '
                        '   Look for a socket with TCP flag equal to the carry flag,
                        '   a nonzero receive buffer pointer, and a local port that
                        '   matches the ip_ports destination port (low word).
                        '
                        '   If a socket is bound, it must be bound to this peer's IP
                        '   and port. If we find an unbound socket, we bind it.
                        '
                        '   If a socket is found successfully, we receive up to
                        '   payload_len bytes into the socket's next buffer, then we
                        '   advance the buffer pointer and packet count.
                        '
socket_rx               cmp     socket, #0 wz           ' Start the search
              if_z      rdword  socket, socket_head_ptr wz
              if_z      jmp     #socket_rx_ret          ' Empty socket list
                        mov     r2, socket              ' Remember first socket visited
        
                        mov     r4, ip_ports            ' Cache IP destination port in high word of r4
                        shl     r4, #16
              if_c      or      r4, #1                  ' Set TCP bit = C. Now r4 is a template for the
                                                        '   socket we're searching for.

:loop                   rdlong  r3, socket              ' Read local port, 'next' pointer, and TCP bit.
                        mov     r0, r3
                        andn    r0, hFFFE               ' Mask off 'next' pointer and X bit.
                        cmp     r0, r4 wz               ' Compare the rest to our template
              if_z      jmp     #:template_match

:next                   call    #socket_next        
              if_nz     jmp     #:loop
                        jmp     #socket_rx_ret          ' Unsuccessful, no socket is listening.

:template_match         mov     sd_rxtx, socket         ' Point sd_rxtx at the RX status field.
                        add     sd_rxtx, #SD_RX
                        call    #socket_load_bd         ' Cache info about the BD, check if it's NULL
              if_z      jmp     #:next                  ' No buffer available. Next...

                        mov     r1, socket              ' Read the IP of the bound peer, if any.
                        add     r1, #SD_PEER_IP
                        rdlong  r0, r1 wz               ' If Z=1, socket is unbound
              if_z      jmp     #:bind                  '  Bind it, then receive.
                        cmp     r0, peer_ip wz                        
              if_nz     jmp     #:next                  ' Wrong peer IP.

                        add     r1, #4                  ' Read peer port and reserved bits
                        rdlong  r0, r1                  '   (Peer port is in high word)
                        xor     r0, ip_ports            ' Compare with source port, in high word
                        testn   r0, hFFFF wz
              if_z      jmp     #:found                 ' If it matches, we found a port bound to this peer.
                        jmp     #:next                  ' Bound to wrong peer port.
              
:bind                   ' Found a socket, but it isn't yet bound to any peer. Bind it.

                        mov     r0, ip_ports
                        wrlong  peer_ip, r1
                        add     r1, #SD_PEER_PORT - SD_PEER_IP
                        shr     r0, #16
                        wrword  r0, r1                        

:found                  ' Found the socket. Now do all the setup for the receive itself.
                        ' The BD has already been loaded, so 'bd' and 'bd_szptr' are valid.

                        mov     r0, bd_szptr            ' Extract just the BD size
                        shr     r0, #16
                        max     payload_len, r0         ' Limit payload length to buffer size
                        wrword  payload_len, bd         ' Write the BD's "actual size" field.

                        call    #socket_next_bd         ' Prepare to swap to the next BD.

                        mov     sx_i1, sx_rx1           ' Prepare the SX loop for receive
                        mov     sx_i2, sx_rx2
                        call    #sx_loop                ' And fire off the Socket Tranfer loop.
socket_rx_ret           ret

                        '
                        ' socket_tx_finish --
                        '
                        '   This routine is called by a transmit protocol handler, after the packet
                        '   header has been set up and it's ready for us to fill in the payload.
                        '
                        '   This routine sends the current socket's transmit buffer payload over SPI,
                        '   and advances the socket to its next transmit buffer.
                        '
                        '   This expects that the socket's buffer descriptor has already been loaded
                        '   by socket_load_bd. The 'bd' and 'bd_szptr' fields are valid.
                        '
                        '   After we finish, this transmits the packet and jumps back to the main loop.
                        '
socket_tx_finish        mov     sx_i1, sx_tx1           ' Prepare the SX loop for transmit
                        mov     sx_i2, sx_tx2
                        call    #sx_loop                ' And fire off the Socket Tranfer loop.
                        add     tx_back_buf_end, spi_write_count
                        jmp     #mainLoop

                        '
                        ' sx_loop --
                        '
                        '   This is our Socket Transfer (SX) engine. It is a reconfigurable
                        '   loop which copies data between SPI and hub memory, with an optional
                        '   byte swap in order to respect the S bit in bd_szptr. To select
                        '   the transfer direction, load sx_i[12] from either sx_rx[12] or
                        '   sx_tx[12].
                        '
                        '   We have separate loops for byte-swapped and non-byte-swapped
                        '   copies, for speed.  The number of instructions in the loop is
                        '   directly proportional to the amount of dead air on the SPI bus
                        '   between 32-bit words, so it's very important for burst performance
                        '   that these loops be as simple as possible.
                        '
sx_loop                 mov     sx_i3, sx_i1            ' Copy rx/tx instructions
                        mov     sx_i4, sx_i2
                        test    bd_szptr, #1 wc         ' Extract S bit.
                        mov     r2, payload_len         ' Init loop counter
                        add     r2, #%11                '   Round up to 32-bit boundary
                        shr     r2, #2                  '   Count in 32-bit words
              if_c      jmp     #sx_i3                  ' Jump to loop for S=1

sx_i1                   nop                             ' Load
                        mov     r0, spi_reg             ' Chip Gracey's elegant 6-instruction byte swap
                        rol     spi_reg, #8
                        ror     r0, #8
                        and     spi_reg, h00FF00FF
                        andn    r0, h00FF00FF
                        or      spi_reg, r0
sx_i2                   nop                             ' Store
                        add     bd_szptr, #4
                        djnz    r2, #sx_i1
                        jmp     #sx_done

sx_i3                   nop                             ' Load
sx_i4                   nop                             ' Store
                        add     bd_szptr, #4
                        djnz    r2, #sx_i3

sx_done                 wrlong  bd, sd_rxtx             ' Atomically advance buffer pointer
sx_loop_ret             ret
sx_rx1                  call    #spi_Read32             ' RX load/store
sx_rx2                  wrlong  spi_reg, bd_szptr
sx_tx1                  rdlong  spi_reg, bd_szptr       ' TX load/store
sx_tx2                  call    #spi_Write32


                        '======================================================
                        ' Frame utilities
                        '======================================================

                        '
                        ' tx_poll --
                        '
                        '   Wait for the transmit hardware to become idle. Once it's idle, swap
                        '   the front and back buffers, and start sending a new packet if we need to.
                        '
tx_poll
                        mov     r1, #ECON1
                        call    #reg_Read
                        test    r2, #TXRTS wz 
              if_nz     djnz    tx_timer, #tx_poll_ret  ' If we haven't timed out, try again later
                        mov     tx_timer, #TX_POLL_TIMEOUT

                        ' Swap front/back. We can do this without a temporary, since front==front_end.
                        cmp     tx_front_buf, tx_front_buf_end wz
              if_z      mov     tx_front_buf_end, tx_back_buf_end
              if_z      mov     tx_back_buf_end, tx_front_buf
              if_z      mov     tx_front_buf, tx_back_buf
              if_z      mov     tx_back_buf, tx_back_buf_end

                        cmp     tx_front_buf, tx_front_buf_end wz
              if_z      jmp     #tx_poll_ret            ' No data to transmit

                        or      reg_ECON1, #TXRST       ' Reset transmitter for Rev B5 errata 10
                        call    #reg_UpdateECON1        ' Toggle TXRST on
                        call    #reg_UpdateECON1        ' Auto-clear TXRST
                        
                        mov     r1, #ETXSTL             ' Set transmit start pointer
                        mov     r2, tx_front_buf
                        call    #reg_Write16

                        mov     r1, #ETXNDL             ' Write transmit end pointer
                        mov     r2, tx_front_buf_end
                        call    #reg_Write16

                        or      reg_ECON1, #TXRTS       ' Start transmitting
                        call    #reg_UpdateECON1

                        ' Next time the transmitter becomes idle, the backbuffer will be free.
                        mov     tx_front_buf_end, tx_front_buf

tx_poll_ret             ret     

                       
                        '======================================================                             
                        ' IPv4 Utilities
                        '======================================================

                        '
                        ' ip_sum32 --
                        '
                        '   Update the 'checksum' variable by performing
                        '   one's complement addition (add the carry bit)
                        '   for each of the 16-bit words in spi_reg. Does
                        '   not modify spi_reg.
                        '
                        '   'checksum' always contains the one's complement
                        '   of an IP-style checksum in its lower 16 bits.
                        '
                        '   Note that we must calculate checksums in software,
                        '   even though the ENC28J60's DMA engine can perform
                        '   them in hardware. This is due to Rev B5 errata 15:
                        '   received packets may be dropped if we use the
                        '   hardware checksum module at any time.
                        '
ip_sum32                shl     checksum, #16           ' Move checksum to upper word, lower word 0
                        add     checksum, spi_reg wc    ' Add high word (ignore low word)
              if_c      add     checksum, h10000        ' Carry one's complement
                        mov     r0, spi_reg             ' Justify low word
                        shl     r0, #16
                        add     checksum, r0 wc         ' Add low word
              if_c      add     checksum, h10000        ' Carry one's complement
                        shr     checksum, #16           ' Move checksum back, discard temp bits
ip_sum32_ret            ret                        
                               

                        '======================================================
                        ' Register Access Layer
                        '======================================================
                        
                        ' This layer implements low-level control over the
                        ' ENC28J60's main register file and PHY registers.
                        ' It's responsible for memory banking, controlling the
                        ' CS line, and performing PHY read/write sequences.
                        
                        '
                        ' reg_Write --
                        '
                        '   Write any 8-bit register other than ECON1, named by r1.
                        '   Uses data from the low 8 bits of r2.
                        '
                        '   Guaranteed not to modify reg_data.
                        '
reg_Write               call    #reg_BankSel
                        call    #spi_Begin
                        or      spi_reg, #SPI_WCR
                        call    #spi_Write8
                        mov     spi_reg, r2
                        call    #spi_Write8
reg_Write_ret           ret

                        '
                        ' reg_UpdateECON1 --
                        '
                        '   This is a multi-function routine for updating bits in ECON1.
                        '   It's actually pretty simple, but we reuse it in various ways
                        '   in order to save code space.
                        '
                        '    - Bank bits are unconditionally set from reg_ECON1, and
                        '      reg_ECON1 is not modified. We send a BFC command to clear
                        '      the hardware's bank bits, then we OR in the correct
                        '      bits in a BFS.
                        '
                        '    - Other bits are OR'ed with the bits in reg_ECON1, and
                        '      those bits in reg_ECON1 are cleared afterwards. This
                        '      lets us queue up 'enable' bits (transmit/receive, reset)
                        '      in reg_ECON1, and this routine transfers those bits to
                        '      the real hardware. We never clear non-bank bits in the
                        '      real ECON1, and we'll never set an ECON1 bit more than
                        '      once unless it was set in reg_ECON1 again.
                        '
                        '    - Reset bits are automatically cleared, along with the bank
                        '      bits. This makes it possible to momentarily reset the
                        '      transmit/receive logic by writing the reset bit to reg_ECON1
                        '      and calling this routine twice.
                        '
reg_UpdateECON1         call    #spi_Begin              ' Clear bank/reset bits
                        mov     spi_reg, #SPI_BFC | (%11111 & ECON1)
                        call    #spi_Write8
                        mov     spi_reg, #BSEL0 | BSEL1 | TXRST | RXRST
                        call    #spi_Write8

                        call    #spi_Begin              ' Set all bits
                        mov     spi_reg, #SPI_BFS | (%11111 & ECON1)
                        call    #spi_Write8
                        mov     spi_reg, reg_ECON1
                        call    #spi_Write8

                        and     reg_ECON1, #$03         ' Clear all local non-bank bits
reg_UpdateECON1_ret     ret

                        '
                        ' reg_Write16 --
                        '
                        '   Write a 16-bit value to a pair of 8-bit registers, named
                        '   by r1 (low) and r1+1 (high). Uses the low
                        '   16-bits of r2.
                        '
                        '   Always writes the high byte last, as is required by
                        '   registers which are latched in hardware after a write.
                        '
reg_Write16             call    #reg_Write
                        add     r1, #1
                        shr     r2, #8
                        call    #reg_Write
reg_Write16_ret         ret

                        '
                        ' reg_Read --
                        '
                        '   Read an 8-bit register, named by r1.
                        '   Returns the value via r2.
                        '
reg_Read                call    #reg_BankSel
                        call    #spi_Begin
                        or      spi_reg, #SPI_RCR
                        call    #spi_Write8
                        test    r1, #$100 wz            ' Read dummy byte?
              if_nz     call    #spi_Read8              
                        call    #spi_Read8
                        mov     r2, spi_reg
reg_Read_ret            ret

                        '
                        ' reg_BankSel --
                        '
                        '   Select the proper bank for the register in r1,
                        '   and load the lower 5 bits of the register name into spi_data.
                        '
                        '   Must not modify reg_data.
                        '
reg_BankSel             test    r1, #$80 wz             ' Is the register unbanked?
              if_nz     mov     r0, r1                  ' Compute difference between...
              if_nz     shr     r0, #5                  '   reg_name[6:5]
              if_nz     xor     r0, reg_ECON1           '   and reg_ECON[1:0]
              if_nz     and     r0, #%11 wz             ' Already in the right bank?
              if_nz     xor     reg_ECON1, r0           ' Set new bank
              if_nz     call    #reg_UpdateECON1                        
                        mov     spi_reg, r1             ' Save lower 5 bits
                        and     spi_reg, #%11111
reg_BankSel_ret         ret


                        '======================================================
                        ' Fast SPI Engine
                        '======================================================
                        
                        ' This SPI engine uses a very carefully timed CTRA to
                        ' generate the clock pulses while an unrolled loop reads
                        ' the bus at two instructions per bit. This gives an SPI
                        ' clock rate 1/8 the system clock. At an 80Mhz system clock,
                        ' that's an SPI data rate of 10 Mbit/sec!
                        '
                        ' Only touch this code if you have an oscilloscope at hand :)
                        '
                        ' If this code wasn't confusing enough, there's another
                        ' complication: To save memory, we don't actually store the
                        ' unrolled SPI loops in hub memory. The initialization segment
                        ' has a code generator which produces the unrolled read/write
                        ' routines. See the comments for spi_Read8/Write8/Read32/Read32,
                        ' the meta-code for these SPI routines is located below, in the
                        ' initialization overlay.

                        '
                        ' spi_WriteBufMem --
                        '
                        '   Begin writing to the ENC28J60's buffer memory, at the
                        '   current write location. Does not affect spi_write_count.
                        '
spi_WriteBufMem         sub     spi_write_count, #1     ' Undo effects of Write8 below
                        call    #spi_Begin
                        mov     spi_reg, #SPI_WBM
                        call    #spi_Write8
spi_WriteBufMem_ret     ret

                        '
                        ' spi_ReadBufMem --
                        '
                        '   Begin reading from the ENC28J60's buffer memory, at the
                        '   current read location. Does not affect spi_write_count.
                        '
spi_ReadBufMem          sub     spi_write_count, #1
                        call    #spi_Begin
                        mov     spi_reg, #SPI_RBM
                        call    #spi_Write8
spi_ReadBufMem_ret      ret
                        
                        '
                        ' spi_Begin --
                        '
                        '   End the previous SPI command, and begin a new one.
                        '   We don't have an explicit spi_End, to save code space.
                        '   The etherCog always begins a new command shortly after
                        '   ending any command, so there is really nothing to gain
                        '   by explicitly ending our commands.
                        '
                        '   The ENC28J60's SPI interface has a setup time and a
                        '   disable time of 50ns each, or one instruction at 80 MHz.
                        '   The hold time is 210ns for MAC and MII register accesses.
                        '   At worst, this requires us to waste 16 extra clock cycles.
                        '   This would be four no-ops, or the equivalent but smaller
                        '   two TJZ/TJNZ instructions which fail to branch.
                        '
spi_Begin               tjz     hFFFF, #0
                        tjz     hFFFF, #0
                        or      outa, cs_mask
                        tjz     hFFFF, #0
                        andn    outa, cs_mask
spi_Begin_ret           ret

                        '
                        ' spi_Read16 --
                        '
                        '   Read 16 bits from the SPI port, and return them in the
                        '   entirety of spi_reg. (Big endian byte order)
                        '
spi_Read16              call    #spi_Read8
                        call    #spi_ShiftIn8
spi_Read16_ret          ret                        

                        '
                        ' spi_Write16 --
                        '
                        '   Write 16 bits to the SPI port, in big endian byte order.
                        '   Increments spi_write_count by 2.
                        '
spi_Write16             shl     spi_reg, #16
                        call    #spi_ShiftOut8
                        call    #spi_ShiftOut8
spi_Write16_ret         ret   
   

'------------------------------------------------------------------------------
' Initialized Data
'------------------------------------------------------------------------------

hFFFF                   long    $FFFF
hFFFE                   long    $FFFE
hFFFC                   long    $FFFC
h00FF00FF               long    $00FF00FF
h10000                  long    $10000
frq_8clk                long    1 << (32 - 3)   ' 1/8th clock rate

pc                      long    0               ' Initialized with @init_entry            

c_rx_buf_end            long    RX_BUF_END
c_ethertype_arp         long    ETHERTYPE_ARP
c_ethertype_ipv4        long    ETHERTYPE_IPV4
c_arp_proto             long    ARP_HW_ETHERNET | ETHERTYPE_IPV4
c_arp_request           long    ARP_LENGTHS | ARP_REQUEST
c_arp_reply             long    ARP_LENGTHS | ARP_REPLY

tx_ip_flags             long    $4000           ' Don't fragment
tx_ip_ttl               long    64 << 24        ' Default IP Time To Live

reg_ECON1               long    RXEN            ' Turn on the receiver at our first UpdateECON1

cs_mask                 long    0               ' Initialized with pin masks
si_mask                 long    0
so_mask                 long    0

socket_head_ptr         long    0               ' Address of list head (word) in hub memory
socket                  long    0               ' Pointer to current socket

tx_front_buf            long    TX_BUF1_START   ' The buffer we're currently transmitting
tx_front_buf_end        long    TX_BUF1_START
tx_back_buf             long    TX_BUF2_START   ' Buffer we're preparing to transmit
tx_back_buf_end         long    TX_BUF2_START
tx_timer                long    0

' XXX: configurable address info

local_MAC_high          long    $1000           ' Private_00:00:01
local_MAC_low           long    $00000001
local_IP                long    $c0a801C8       ' 192.168.1.200


'------------------------------------------------------------------------------
' Uninitialized Data
'------------------------------------------------------------------------------

' Note that some of our uninitialized data is overlaid with the
' initialization-only code and data at the beginning of the cog.
' These are the rest.

r0                      res     1               ' Temp, needed during early init

r4                      res     1

payload_len             res     1               ' Length of TCP/UDP payload
proto                   res     1               ' Ethernet/IP protocol temp
checksum                res     1               ' Current checksum

sd_rxtx                 res     1               ' Pointer to Socket Descriptor RX/TX word
bd                      res     1               ' Current buffer descriptor address
bd_szptr                res     1               ' Actual size and pointer for current buffer

ip_ports                res     1               ' TCP/UDP ports (high: source, low: dest) 

'
' This is a template for the SPI routines which we unroll
' at initialization time. This must be kept in sync with
' the actual loop unrolling code in the initialization overlay.
'

init_data
spi_Write8              res     1
spi_ShiftOut8           res     21
spi_ShiftOut8_ret
spi_Write8_ret          res     1
spi_Write32             res     69
spi_Write32_ret         res     1
spi_Read8               res     1
spi_ShiftIn8            res     19
spi_ShiftIn8_ret
spi_Read8_ret           res     1
spi_Read32              res     67
spi_Read32_ret          res     1

                        fit

                        
'==============================================================================
' Initialization overlay
'==============================================================================

' This is a hub memory area used for initialization instructions.
' We perform hardware initialization entirely in Spin, but this section
' is used for a sort of meta-LMM execution engine which both initializes
' the driver cog itself, and which performs load-time loop unrolling.
' See the driver cog's main entry point for details.

                        org
init_entry

                        mov     dira, init_dira         ' Take control over the SPI bus
                        mov     ctra, init_ctra
                        
                        wrlong  h10000, par             ' Tell the Spin cog we have the bus
:ack_loop               rdlong  r0, par                 ' Wait for Spin to release the bus
                        test    r0, h10000 wc           '   (We can't use the Z flag. This is an arbitrary single bit.)
:ack_loop_rel     if_c  sub     pc, #4*(:ack_loop_rel + 1 - :ack_loop)                               

                        '
                        ' spi_Write8 --
                        '
                        '   Write the upper 8 bits of spi_reg to the SPI port.
                        '   Increments spi_write_count by 1.
                        '
                        ' spi_ShiftOut8 --
                        '
                        '   A variant of Write8 which doesn't justify spi_reg first.
                        '

        if_never        shl     spi_reg, #24            ' (spi_Write8)    Left justify MSB
        if_never        rcl     spi_reg, #1 wc          ' (spi_ShiftOut8) Shift bit 7
        if_never        mov     phsa, #0                ' Rising edge at center of each bit
        if_never        muxc    outa, si_mask           ' Output bit 7
        if_never        mov     frqa, frq_8clk          ' First clock edge, period of 8 clock cycles

:spiw8_loop             mov     r0, #6                  ' Repeat 7 times, for bits 6..0

        if_never        rcl     spi_reg, #1 wc
        if_never        muxc    outa, si_mask         

                        sub     r0, #1 wc
:spiw8_loop_rel   if_nc sub     pc, #4*(:spiw8_loop_rel - :spiw8_loop)

        if_never        add     spi_write_count, #1     ' Finish last clock cycle and update spi_write_count
        if_never        mov     frqa, #0                ' Turn off clock
        if_never        andn    outa, si_mask           ' Turn off SI
        if_never        ret                             ' (spi_ShiftOut8_ret / spi_Write8_ret)

                        '
                        ' spi_Write32 --
                        '
                        '   Write entire 32-bit contents of spi_reg to the SPI port.
                        '   Increments spi_write_count by 4.
                        ' 

        if_never        rcl     spi_reg, #1 wc          ' (spi_Write32) Shift bit 31
        if_never        mov     phsa, #0                ' Rising edge at center of each bit
        if_never        muxc    outa, si_mask           ' Output bit 31
        if_never        mov     frqa, frq_8clk          ' First clock edge, period of 8 clock cycles

:spiw32_loop            mov     r0, #30                 ' Repeat 31 times, for bits 30..0

        if_never        rcl     spi_reg, #1 wc
        if_never        muxc    outa, si_mask

                        sub     r0, #1 wc
:spiw32_loop_rel  if_nc sub     pc, #4*(:spiw32_loop_rel - :spiw32_loop)

        if_never        add     spi_write_count, #4     ' Finish last clock cycle and update spi_write_count
        if_never        mov     frqa, #0                ' Turn off clock
        if_never        andn    outa, si_mask           ' Turn off SI
        if_never        ret                             ' (spi_Write32_ret)

                        '
                        ' spi_Read8 --
                        '
                        '   Read 8 bits from the SPI port, and return them in the lower 8
                        '   bits of spi_reg.
                        '
                        ' spi_ShiftIn8 --
                        '
                        '   A variant of Read8 that doesn't clear the spi_reg, but shifts it
                        '   left by 8 bits as we read into the 8 LSBs.
                        '

        if_never        mov     spi_reg, #0             ' (spi_Read8)    Clear unused bits
        if_never        mov     phsa, #0                ' (spi_ShiftIn8) Rising edge at center of each bit
        if_never        mov     frqa, frq_8clk          ' First clock edge, period of 8 clock cycles

:spir8_loop             mov     r0, #6                  ' Repeat 7 times, for bits 7..1

        if_never        test    so_mask, ina wc
        if_never        rcl     spi_reg, #1

                        sub     r0, #1 wc
:spir8_loop_rel   if_nc sub     pc, #4*(:spir8_loop_rel - :spir8_loop)

        if_never        test    so_mask, ina wc         ' Sample bit 0
        if_never        mov     frqa, #0                ' Turn off clock
        if_never        rcl     spi_reg, #1             ' Store bit 0
        if_never        ret                             ' (spi_ShiftIn8_ret / spi_Read8_ret)

                        '
                        ' spi_Read32 --
                        '
                        '   Read 32 bits from the SPI port, and return them in the
                        '   entirety of spi_reg. (Big endian byte order)
                        '
                        
        if_never        mov     phsa, #0                ' (spi_Read32) Rising edge at center of each bit
        if_never        mov     frqa, frq_8clk          ' First clock edge, period of 8 clock cycles

:spir32_loop            mov     r0, #30                 ' Repeat 31 times, for bits 31..1

        if_never        test    so_mask, ina wc
        if_never        rcl     spi_reg, #1

                        sub     r0, #1 wc
:spir32_loop_rel  if_nc sub     pc, #4*(:spir32_loop_rel - :spir32_loop)
                        
        if_never        test    so_mask, ina wc         ' Sample bit 0
        if_never        mov     frqa, #0                ' Turn off clock
        if_never        rcl     spi_reg, #1             ' Store bit 0
        if_never        ret                             ' (spi_Read32_ret)

                        '
                        ' Initialization is done. Enable packet reception, and enter the main loop.
                        '                        
                        call    #reg_UpdateECON1
                        jmp     #mainLoop


'==============================================================================
' Initialization Tables
'==============================================================================

                        '
                        ' reg_init_table --
                        '
                        '   This is a table of register names and their initial values.
                        '   Almost any non-PHY (ETH/MAC) register can be specified here.
                        '   The register names include bank information, so no explicit
                        '   bank switches are necessary.
                        '
                        '   ECON1 cannot be written from this table, it is special
                        '   cased because of how it's used internally for bank switching.
                        '
                        '   During initialization, ECON1 is always zero. After the driver
                        '   cog is fully initialized, it sets RXEN to turn on the receiver.
                        '
reg_init_table
                        ' Automatic buffer pointer increment, no power save mode.

                        byte    ECON2,     AUTOINC

                        ' Disable interrupts, clear interrupt flags.
                        '
                        ' Since we have a dedicated cog on the Propeller,
                        ' there isn't really anything for us to gain by enabling
                        ' interrupts. It will increase code size, and it won't
                        ' decrease receive latency at all. The only real benefit is
                        ' that it would decrease the average latency in detecting
                        ' event sources other than the ENC28J60, such as new transmit
                        ' data from other cogs.

                        byte    EIE,       0
                        byte    EIR,       DMAIF | TXIF | TXERIF | RXERIF
                        
                        ' Receive buffer allocation.
                        '
                        ' Note that we don't have to explicitly allocate the transmit
                        ' buffer now- we set ETXST/ETXND only when we have a specific
                        ' frame ready to transmit.                        

                        byte    ERXSTL,    RX_BUF_START & $FF
                        byte    ERXSTH,    RX_BUF_START >> 8
                        byte    ERXNDL,    RX_BUF_END & $FF
                        byte    ERXNDH,    RX_BUF_END >> 8

                        ' Initial position of the RX read pointer. This is the boundary
                        ' address, indicating how much of the FIFO space is available to
                        ' the MAC. The hardware will write to all bytes up to but not
                        ' including this one.
                        '
                        ' Order matters: we must write high byte last.
                        
                        byte    ERXRDPTL,  RX_BUF_END & $FF 
                        byte    ERXRDPTH,  RX_BUF_END >> 8

                        ' Default SPI read pointer. We initialize this at the beginning
                        ' of the read buffer, and we just let it follow us around the FIFO
                        ' as we receive frames.

                        byte    ERDPTL,    RX_BUF_START & $FF
                        byte    ERDPTH,    RX_BUF_START >> 8
                        
                        ' Receive filters.
                        '
                        ' The ENC28J60 supports several types of packet filtering,
                        ' including an advanced hash table filter and a pattern matching
                        ' filter. Currently we don't use these features. Just program it
                        ' to accept any broadcast packets, and any unicast packets directed
                        ' at this node's MAC address. Also, have the chip verify CRC in
                        ' hardware, and reject any packets with bad CRCs.
                        '
                        ' If you want to run in promiscuous mode, set ERXFCON to 0. Note
                        ' that some of the protocol handling code in etherCog assumes that
                        ' all received packets are addressed to our MAC address, so other
                        ' changes will be necessary.

                        byte    ERXFCON,   UCEN | CRCEN | BCEN
                        
                        ' MAC initialization.
                        '
                        ' Enable the MAC to receive frames, and enable IEEE flow control.
                        ' Ignore control frames. (Don't pass them on to the filter.)

                        byte    MACON1,    TXPAUS | RXPAUS | MARXEN

                        ' Half-duplex mode, padding to 60 bytes, and hardware CRC on
                        ' transmit. Also enable hardware frame length checking. 

                        byte    MACON3,    TXCRCEN | PADCFG0 | FRMLNEN

                        ' For IEEE 802.3 compliance, wait indefinitely for the medium to
                        ' become free before starting a transmission.

                        byte    MACON4,    DEFER

                        ' Back-to-back inter-packet gap setting.
                        ' The minimum gap specified by the IEEE is 9.6us, encoded
                        ' here as $15 for full-duplex and $12 for half-duplex. 
                        
                        byte    MABBIPG,   $12

                        ' The non-back-to-back inter-packet gap. The datasheet
                        ' recommends $0c12 for half-duplex applocations, or $0012
                        ' for full-duplex.

                        byte    MAIPGL,    $12
                        byte    MAIPGH,    $0c

                        ' Maximum permitted frame length, including header and CRC.

                        byte    MAMXFLL,   MAX_FRAME_LEN & $FF
                        byte    MAMXFLH,   MAX_FRAME_LEN >> 8

                        ' Retransmission maximum and collision window, respectively.
                        ' These values are used for half-duplex links.
                        ' The current values here are the hardware defaults,
                        ' included for completeness.

                        byte    MACLCON1,  $0F
                        byte    MACLCON2,  $37

                        ' XXX: MAC address

                        byte    MAADR1,    $10
                        byte    MAADR2,    $00
                        byte    MAADR3,    $00
                        byte    MAADR4,    $00
                        byte    MAADR5,    $00
                        byte    MAADR6,    $01

                        ' Now initialize PHY registers. We have few enough PHY regs
                        ' that doesn't save us space to have a separate table of PHY
                        ' registers. It's cheaper to just encode them manually in this
                        ' table. Some things to note:
                        '
                        '   - We must write the low byte first, high byte last.
                        '     Writing the high byte actually triggers the PHY write.
                        '
                        '   - Normally we'd need to wait for the write to complete,
                        '     but the initialization-only SPI code is so slow that
                        '     by comparison the PHY completes pretty much instantly.
                        '     (PHY writes take ~10us, our Spin SPI code is about 40us
                        '     per bit period!)

                        ' Diable half-duplex loopback (Explicitly turn off the receiver
                        ' when we're transmitting on a half-duplex link.) This bit is ignored
                        ' in full-duplex mode.

                        byte    MIREGADR,   PHCON2
                        byte    MIWRL,      HDLDIS & $FF
                        byte    MIWRH,      HDLDIS >> 8

                        ' PHY in normal operation (no loopback, no power-saving mode)
                        ' and we're forcing half-duplex operation. Without forcing
                        ' half- or full-duplex, it will autodetect based on the polarity
                        ' of an external LED. We want to be sure the PHY and MAC agree
                        ' on duplex configuration.

                        byte    MIREGADR,   PHCON1
                        byte    MIWRL,      0
                        byte    MIWRH,      0

                        ' Disable PHY interrupts
                        
                        byte    MIREGADR,   PHIE
                        byte    MIWRL,      0
                        byte    MIWRH,      0

                        ' LED configuration. See the definition of PHLCON_INIT above.

                        byte    MIREGADR,   PHLCON
                        byte    MIWRL,      PHLCON_INIT & $FF
                        byte    MIWRH,      PHLCON_INIT >> 8

                        ' End of table
                        byte    0


' End of recyclable memory segments
recycle_region_end


'==============================================================================
' Large Memory Model overlay
'==============================================================================

' This is where we put large non-speed-critical portions of the
' driver cog: protocol handling, mostly. This code follows
' normal LMM rules. You can jump to cog addresses directly,
' but to jump to a LMM address you must use LMM primitives.
'
' Since we can't create const references to addresses in hub
' memory, we must calculate LMM addresses relative to lmm_base.

                        org
lmm_base_label

                        '======================================================
                        ' ARP Protocol
                        '======================================================

                        '
                        ' rx_arp --
                        '
                        '   Handle an incoming ARP packet. If it's an ARP request
                        '   for our IP address, send a reply. Currently we ignore
                        '   all other ARP packets.
                        '                        
rx_arp
                        ' First 32 bits: Hardware type and protocol type.
                        ' Verify that these are Ethernet and IPv4, respectively.
                        ' If not, ignore the packet.

                        call    #spi_read32
                        cmp     spi_reg, c_arp_proto wz
              if_nz     jmp     #rx_frame_finish

                        ' The next 32 bits: Upper half is constant (address lengths),
                        ' lower half indicates whether this is a request or reply.
                        ' For now, we drop any packet that isn't a request. 

                        call    #spi_read32
                        cmp     spi_reg, c_arp_request wz
              if_nz     jmp     #rx_frame_finish

                        ' Next 48 bits: Sender Hardware Address (SHA).
                        ' Verify that this matches the peer MAC address. If not, someone
                        ' is lying and we should drop the packet.

                        call    #spi_read16
                        cmp     spi_reg, peer_MAC_high wz
              if_nz     jmp     #rx_frame_finish 
                        call    #spi_read32
                        cmp     spi_reg, peer_MAC_low wz
              if_nz     jmp     #rx_frame_finish

                        ' Next 32 bits: Sender Protocol Address (SPA).
                        ' This is the IP address of the sender.

                        call    #spi_read32
                        mov     peer_IP, spi_reg

                        ' Next 48 bits: Target Hardware Address (THA).
                        ' This field is ignored in ARP requests.

                        call    #spi_read16
                        call    #spi_read32

                        ' Next 32 bits: Target Protocol Address (TPA).
                        ' If this is our IP address, we're the target!
                        ' If not, ignore the packet.
                        
                        call    #spi_read32
                        cmp     spi_reg, local_IP wz
              if_nz     jmp     #rx_frame_finish

                        ' Prepare an ARP reply frame. This is written into
                        ' the transmit back-buffer, which we can start transmitting
                        ' at the next tx_poll. If the buffer is busy, we wait for it
                        ' to become available.

                        mov     proto, c_ethertype_arp  ' Start an ARP reply
                        mov     r0, #tx_begin
                        jmp     #lmm_call                                     

                        mov     spi_reg, c_arp_proto    ' Hardware type and protocol type
                        call    #spi_Write32

                        mov     spi_reg, c_arp_reply    ' Lengths, reply opcode
                        call    #spi_Write32

                        mov     spi_reg, local_MAC_high ' Sender Hardware Address: local MAC
                        call    #spi_Write16
                        mov     spi_reg, local_MAC_low
                        call    #spi_Write32

                        mov     spi_reg, local_IP       ' Sender Protocol Address: Local IP
                        call    #spi_Write32

                        mov     spi_reg, peer_MAC_high  ' Target Hardware Address: SA
                        call    #spi_Write16
                        mov     spi_reg, peer_MAC_low
                        call    #spi_Write32

                        mov     spi_reg, peer_IP        ' Target Protocol Address: Sender's IP
                        call    #spi_Write32

                        ' Finish the reply packet
                        add     tx_back_buf_end, spi_write_count
                        jmp     #rx_frame_finish


                        '======================================================
                        ' IPv4 Protocol
                        '======================================================

                        '
                        ' rx_ipv4 --
                        '
                        '   Receive handler for IPv4 frames. Validate and store
                        '   the IP header, then dispatch to a protocol-specific handler.
                        '
rx_ipv4
                        ' First 32 bits of IP header: Version, header length,
                        ' Type of Service, and Total Length. Verify the version
                        ' and IP header length is what we support, and store the
                        ' IP packet length.

                        call    #spi_read32
                        mov     ip_length, spi_reg
                        and     ip_length, hFFFF
                        shr     spi_reg, #24
                        cmp     spi_reg, #IP_HEADER_LEN | (IP_VERSION << 4) wz
              if_nz     jmp     #rx_frame_finish        ' Includes unsupported IP options

                        ' Second 32 bits: Identification word, flags, fragment
                        ' offset. We ignore the identification word, and make
                        ' sure the More Fragments flag and fragment offset are all
                        ' zero. We don't support fragmented IP packets, so this is
                        ' where they get dropped.

                        call    #spi_read32
                        shl     spi_reg, #16            ' Ignore identification
                        shl     spi_reg, #2 wz          ' Ignore Don't Fragment and Reserved
                        rcl     spi_reg, #1 wc          ' Extract More Fragments bit
           if_nz_or_c   jmp     #rx_frame_finish        ' Fragmented packet       

                        ' Third 32 bits: TTL, protocol, header checksum. We don't
                        ' bother checking the checksum, and we aren't routing
                        ' packets, so all we care about is the protocol. Stow it
                        ' temporarily in r1.

                        call    #spi_read32
                        mov     r1, spi_reg
                        shr     r1, #16
                        and     r1, #$FF

                        ' Fourth 32 bits: Source address. Store it.

                        call    #spi_read32
                        mov     peer_IP, spi_reg

                        ' Fifth 32 bits: Destination address. Make sure this
                        ' packet is for us. If not, drop it.
                        '
                        ' Note that we don't support broadcast IP yet.
                        ' All broadcast IP packets are dropped. (But this
                        ' is usually a good thing...)

                        call    #spi_read32
                        cmp     spi_reg, local_IP wz
              if_nz     jmp     #rx_frame_finish        ' Packet not for us

                        ' We know there are no option words (we checked the IP
                        ' header length) so the rest of this frame is protocol
                        ' data. Branch to a protocol-specific handler, in the
                        ' LMM overlay.

                        cmp     r1, #IP_PROTO_UDP wz
              if_z      mov     r0, #rx_udp
              if_z      jmp     #lmm_vm

                        cmp     r1, #IP_PROTO_TCP wz
              if_z      mov     r0, #rx_tcp
              if_z      jmp     #lmm_vm

                        cmp     r1, #IP_PROTO_ICMP wz
              if_z      mov     r0, #rx_icmp
              if_z      jmp     #lmm_vm

                        ' No handler.. drop the packet
                        jmp     #rx_frame_finish
                        
                        '
                        ' tx_ipv4 --
                        '
                        '   Start transmitting an IPv4 packet. Waits for the
                        '   transmit back-buffer to become available if necessary.
                        '   Assembles Ethernet and IPv4 headers using peer_MAC,
                        '   peer_IP, ip_length, and proto.
                        '
tx_ipv4
                        shl     proto, #16              ' Move IP protocol to upper 16 bits
                        or      proto, c_ethertype_ipv4 ' Ethernet protocol is IPv4
                        mov     r0, #tx_begin           ' Write Ethernet frame
                        jmp     #lmm_call
                        mov     checksum, #0            ' Reset checksum
                        
                        ' First 32 bits of IP header: Version, header length,
                        ' Type of Service, and Total Length.

                        mov     spi_reg, #IP_HEADER_LEN | (IP_VERSION << 4)
                        shl     spi_reg, #24
                        or      spi_reg, ip_length
                        call    #ip_sum32
                        call    #spi_Write32

                        ' Second 32 bits: Identification word, flags, fragment
                        ' offset.

                        mov     spi_reg, tx_ip_flags
                        call    #ip_sum32
                        call    #spi_Write32
                        
                        ' Third 32 bits: TTL, protocol, header checksum.
                        ' Protocol comes from 'proto', which is now shifted
                        ' into place properly. Use a default TTL.

                        mov     spi_reg, local_ip       ' Add local/peer IPs to checksum
                        call    #ip_sum32
                        mov     spi_reg, peer_ip
                        call    #ip_sum32                        
                        
                        mov     spi_reg, proto
                        or      spi_reg, tx_ip_ttl
                        andn    spi_reg, hFFFF          ' Zero checksum field
                        call    #ip_sum32               ' Add other bits to checksum
                        xor     checksum, hFFFF         ' Finish checksum
                        or      spi_reg, checksum       '   .. and include it

                        call    #spi_Write32

                        ' Fourth 32 bits: Source address. This is us.

                        mov     spi_reg, local_IP
                        call    #spi_Write32

                        ' Fifth 32 bits: Destination address. This is our peer.

                        mov     spi_reg, peer_IP
                        call    #spi_Write32

                        jmp     #lmm_ret


                        '======================================================
                        ' ICMP protocol
                        '======================================================

                        '
                        ' rx_icmp --
                        '
                        '   We may care about other ICMP message types in the future,
                        '   but for now this just responds to Echo Request messages (pings).
                        '
                        '   We copy the ping data directly from the receive FIFO to the
                        '   transmit back-buffer, so we can handle any non-fragmented ping
                        '   size (up to the maximum ethernet frame size). This is slow,
                        '   but it doesn't require any hub memory.
                        '
                        '   We also take a shortcut on calculating the ICMP checksum.
                        '   Instead of calculating our own checksum (which requires examining
                        '   the entire packet data), we just modify the sender's checksum
                        '   to account for our header changes. If the sender's checksum was
                        '   right, our reply will be right.
                        '
rx_icmp
                        call    #spi_Read32             ' Receive header word
                        mov     r3, spi_reg
                        
                        ror     r3, #24                 ' Select type byte
                        sub     r3, #ICMP_ECHO_REQUEST
                        test    r3, #$FF wz             ' Is type byte Echo Request?
              if_nz     jmp     #rx_frame_finish        ' Not an echo request, ignore.
                        rol     r3, #24
              
                        ' Now we need to replace the type with an echo reply.
                        ' Actually, since Echo Reply is zero, we already did that
                        ' as a side-effect. Now we just have to patch the checksum.

                        mov     checksum, r3            ' Separate out the original checksum
                        andn    r3, hFFFF
                        and     checksum, hFFFF
                        xor     checksum, hFFFF         ' Undo one's complement
                        mov     spi_reg, #ICMP_ECHO_REQUEST
                        shl     spi_reg, #8
                        sub     checksum, spi_reg wc    ' One's complement subtraction
              if_c      sub     checksum, #1
                        and     checksum, hFFFF
                        xor     checksum, hFFFF         ' Put it back in
                        or      r3, checksum

                        mov     proto, #IP_PROTO_ICMP   ' Start transmitting an ICMP packet
                        mov     r0, #tx_ipv4
                        jmp     #lmm_call

                        mov     spi_reg, r3             ' Send the ICMP header
                        call    #spi_Write32

                        sub     ip_length, #20          ' Subtract IP header length
:loop                   sub     ip_length, #4 wz,wc     ' Round up to a 32-bit boundary
          if_z_or_c     add     tx_back_buf_end, spi_write_count
          if_z_or_c     jmp     #rx_frame_finish

                        call    #spi_ReadBufMem         ' Copy 32 bits from RX to TX
                        call    #spi_Read32
                        mov     r3, spi_reg
                        call    #spi_WriteBufMem
                        mov     spi_reg, r3
                        call    #spi_Write32

:loop_rel               sub     pc, #4*(:loop_rel + 1 - :loop)


                        '======================================================
                        ' UDP protocol
                        '======================================================

                        '
                        ' rx_udp --
                        '
                        '   Handle incoming UDP packets. This decodes the tiny UDP
                        '   header, looks for a matching Socket Descriptor, and
                        '   delivers the packet if possible.
                        '
rx_udp
                        call    #spi_Read32             ' Read source/dest ports
                        mov     ip_ports, spi_reg

                        call    #spi_Read32             ' Ignore checksum, save length
                        shr     spi_reg, #16
                        sub     spi_reg, #8 wc,wz       ' Remove UDP header size
        if_c_or_z       jmp     #rx_frame_finish        ' Drop packets that are too small

                        mov     payload_len, spi_reg wc ' Save length of UDP payload, also set C=0
                        call    #socket_rx              ' Read the payload data into a UDP socket
                        jmp     #rx_frame_finish

                        '
                        ' tx_udp --
                        '
                        '   Prepare an outgoing UDP packet. This starts transmitting a new IP
                        '   packet, and adds a UDP header with the correct source/dest ports
                        '   and size. It then calls back into the socket layer to provide the
                        '   packet's payload.
                        '
tx_udp
                        mov     proto, #IP_PROTO_UDP    ' Start transmitting, send IP header
                        mov     r0, #tx_ipv4
                        jmp     #lmm_call

                        mov     spi_reg, ip_ports       ' Write source/dest ports
                        call    #spi_Write32

                        mov     spi_reg, payload_len    ' Send length word, no checksum (zero)
                        add     spi_reg, #8             ' Add UDP header size
                        shl     spi_reg, #16
                        call    #spi_Write32

                        jmp     #socket_tx_finish       ' Ask the socket layer to send our payload


                        '======================================================
                        ' TCP protocol
                        '======================================================

rx_tcp
                        ' XXX, not yet
                        jmp     #rx_frame_finish


tx_tcp
                        ' XXX, not yet
                        jmp     #mainLoop


                        '======================================================
                        ' Ethernet Frame Layer
                        '======================================================

                        '
                        ' rx_frame --
                        '
                        '   Receive a single Ethernet frame header, and dispatch
                        '   to an appropriate handler for the rest of the frame.
                        '   The handler returns to rx_frame_finish, where we
                        '   acknowledge that we've finished processing the frame.
                        '
                        '   Must only be called when a packet is waiting (EPKTCNT > 0)
                        '                        
rx_frame
                        ' The read pointer (ERDPTR) is already pointed at the beginning
                        ' of the first available packet. Start reading it...

                        call    #spi_ReadBufMem

                        call    #spi_Read8              ' Read 16-bit Next Packet Pointer, low byte first. 
                        mov     rx_next, spi_reg        '   (spi_Read16 would give us the wrong byte order)   
                        call    #spi_Read8
                        shl     spi_reg, #8
                        or      rx_next, spi_reg

                        call    #spi_Read32             ' Ignore 32-bit status vector
                        
                        ' At this point, we've read the ENC28J60's header, and all
                        ' subsequent data is from the actual Ethernet frame:
                        '
                        '    1. 48-bit destination address
                        '    2. 48-bit source address
                        '    3. 16-bit EtherType
                        '
                        ' We ignore the destination address, since we already know
                        ' that (due to the hardware filter) this packet is for us. It
                        ' may be a multicast or a unicast packet. If we need to know
                        ' which it was, we could save the receive status word.
                        '
                        ' We store the source address, since it's usually necessary
                        ' to create reply packets.
                        '
                        ' The EtherType tells us what protocol the rest of the packet
                        ' uses. We only care about IP and ARP. Other EtherTypes are
                        ' ignored.

                        call    #spi_Read32             ' Ignore upper 32 bits of DA
                        call    #spi_Read32             ' Ignore lower 16 bits of DA, store upper 16 bits of SA
                        and     spi_reg, hFFFF
                        mov     peer_MAC_high, spi_reg
                        call    #spi_Read32             ' Store lower 32 bits of SA
                        mov     peer_MAC_low, spi_reg

                        call    #spi_Read16             ' Read EtherType. This tells us what protocol the
                                                        ' rest of the frame is using.
                        
                        ' Branch out to protocol-specific handlers, in our LMM overlay.
                        ' They all jump back to rx_frame_finish when they're done.

                        cmp     spi_reg, c_ethertype_ipv4 wz
              if_z      mov     r0, #rx_ipv4
              if_z      jmp     #lmm_vm

                        cmp     spi_reg, c_ethertype_arp wz
              if_z      mov     r0, #rx_arp
              if_z      jmp     #lmm_vm
                        
rx_frame_finish_lmm     ' The rx_frame_finish trampoline jumps here...                   

                        ' Now we're done with the frame. Either we read the whole thing,
                        ' or we decided to ignore it. Free up this buffer space, and
                        ' prepare to read the next frame.

                        mov     r1, #ERDPTL             ' Set read pointer to the next frame
                        mov     r2, rx_next
                        call    #reg_Write16

                        mov     r2, rx_next             ' Compute ERXRDPT such that it's always
                        sub     r2, #1 wc               '    odd. This is Rev B5 errata 11.
              if_c      mov     r2, c_rx_buf_end
                        mov     r1, #ERXRDPTL           ' Write it
                        call    #reg_Write16
                        
                        mov     r1, #ECON2              ' Acknowledge the interrupt
                        mov     r2, #(AUTOINC | PKTDEC)
                        call    #reg_Write

                        sub     rx_pktcnt, #1 wz        ' Decrement local packet count                        
              if_z      jmp     #mainLoop_rx_done       ' Back to the main loop if we're done. If not, loop.
:rel                    sub     pc, #4*(:rel + 1 - rx_frame)

                        '
                        ' tx_begin --
                        '
                        '   Begin preparing a new frame for transmission,
                        '   and write the ethernet frame header.
                        '
                        '   Transmission is double-buffered, so this can be used
                        '   even if the hardware is still busy transmitting the
                        '   'front' buffer's frame.
                        '
                        '   This routine will start writing into the transmit
                        '   back buffer. The caller should start writing an ethernet
                        '   frame using the spi_Write functions. When finished, the
                        '   packet is made ready to transmit by adding spi_write_count
                        '   to tx_back_buf_end.
                        '
tx_begin                cmp     tx_back_buf, tx_back_buf_end wz
:rel1         if_z      add     pc, #4*(:ready - :rel1 - 1)
                        call    #tx_poll
:rel2                   sub     pc, #4*(:rel2 + 1 - tx_begin)

:ready                  mov     r1, #EWRPTL             ' Set SPI write pointer
                        mov     r2, tx_back_buf
                        call    #reg_Write16

                        call    #spi_WriteBufMem

                        mov     spi_reg, #0             ' Write control byte (zero, no overrides needed)
                        call    #spi_Write8

                        mov     spi_write_count, #0     ' Start counting written bytes. We start after
                                                        '   the control byte, because we actually want
                                                        '   one less than the number of total bytes, so
                                                        '   that we can add this number to the tx_back_buf
                                                        '   pointer to get a pointer to the last byte in
                                                        '   the frame.

                        mov     spi_reg, peer_MAC_high  ' Destination Address
                        call    #spi_Write16
                        mov     spi_reg, peer_MAC_low
                        call    #spi_Write32

                        mov     spi_reg, local_MAC_high ' Source Address
                        call    #spi_Write16
                        mov     spi_reg, local_MAC_low
                        call    #spi_Write32

                        mov     spi_reg, proto          ' EtherType (protocol)
                        call    #spi_Write16

                        jmp     #lmm_ret


CON

'==============================================================================
' ENC28J60 Constants
'==============================================================================

' All the constants in this section are defined by the ENC28J60 data sheet.
' They should not be changed.

' SPI Commands

SPI_RCR = %000_00000   ' Read Control Register
SPI_RBM = %001_11010   ' Read Buffer Memory
SPI_WCR = %010_00000   ' Write Control Register
SPI_WBM = %011_11010   ' Write Buffer Memory
SPI_BFS = %100_00000   ' Bit Field Set
SPI_BFC = %101_00000   ' Bit Field Clear
SPI_SRC = %111_11111   ' System Reset Command

' Register names.
'
' Each register's address is encoded: Bits 4:0 are the register's
' position within its bank, bits 6:5 are its bank number, bit
' 7 is cleared if the register is available in all banks, and bit 8
' is set if the register will be preceeded by a dummy byte on read.
' Bit 8 is not necessary for writes. (Our register write tables store
' encoded register names in a single byte.)
'
' These encoded register names can be used with the reg_Read and reg_Write routines.

' All banks
EIE       = (%00_00 << 5) | $1B
EIR       = (%00_00 << 5) | $1C
ESTAT     = (%00_00 << 5) | $1D
ECON2     = (%00_00 << 5) | $1E
ECON1     = (%00_00 << 5) | $1F

' Bank 0      
ERDPTL    = (%01_00 << 5) | $00
ERDPTH    = (%01_00 << 5) | $01
EWRPTL    = (%01_00 << 5) | $02
EWRPTH    = (%01_00 << 5) | $03
ETXSTL    = (%01_00 << 5) | $04
ETXSTH    = (%01_00 << 5) | $05
ETXNDL    = (%01_00 << 5) | $06
ETXNDH    = (%01_00 << 5) | $07
ERXSTL    = (%01_00 << 5) | $08
ERXSTH    = (%01_00 << 5) | $09
ERXNDL    = (%01_00 << 5) | $0A
ERXNDH    = (%01_00 << 5) | $0B
ERXRDPTL  = (%01_00 << 5) | $0C
ERXRDPTH  = (%01_00 << 5) | $0D
ERXWRPTL  = (%01_00 << 5) | $0E
ERXWRPTH  = (%01_00 << 5) | $0F
EDMASTL   = (%01_00 << 5) | $10
EDMASTH   = (%01_00 << 5) | $11
EDMANDL   = (%01_00 << 5) | $12
EDMANDH   = (%01_00 << 5) | $13
EDMADSTL  = (%01_00 << 5) | $14
EDMADSTH  = (%01_00 << 5) | $15
EDMACSL   = (%01_00 << 5) | $16
EDMACSH   = (%01_00 << 5) | $17
              
' Bank 1
EHT0      = (%01_01 << 5) | $00
EHT1      = (%01_01 << 5) | $01
EHT2      = (%01_01 << 5) | $02
EHT3      = (%01_01 << 5) | $03
EHT4      = (%01_01 << 5) | $04
EHT5      = (%01_01 << 5) | $05
EHT6      = (%01_01 << 5) | $06
EHT7      = (%01_01 << 5) | $07
EPMM0     = (%01_01 << 5) | $08
EPMM1     = (%01_01 << 5) | $09
EPMM2     = (%01_01 << 5) | $0A
EPMM3     = (%01_01 << 5) | $0B
EPMM4     = (%01_01 << 5) | $0C
EPMM5     = (%01_01 << 5) | $0D
EPMM6     = (%01_01 << 5) | $0E
EPMM7     = (%01_01 << 5) | $0F
EPMCSL    = (%01_01 << 5) | $10
EPMCSH    = (%01_01 << 5) | $11
EPMOL     = (%01_01 << 5) | $14
EPMOH     = (%01_01 << 5) | $15
ERXFCON   = (%01_01 << 5) | $18
EPKTCNT   = (%01_01 << 5) | $19
              
' Bank 2
MACON1    = (%11_10 << 5) | $00
MACON3    = (%11_10 << 5) | $02
MACON4    = (%11_10 << 5) | $03
MABBIPG   = (%11_10 << 5) | $04
MAIPGL    = (%11_10 << 5) | $06
MAIPGH    = (%11_10 << 5) | $07
MACLCON1  = (%11_10 << 5) | $08
MACLCON2  = (%11_10 << 5) | $09
MAMXFLL   = (%11_10 << 5) | $0A
MAMXFLH   = (%11_10 << 5) | $0B
MICMD     = (%11_10 << 5) | $12
MIREGADR  = (%11_10 << 5) | $14
MIWRL     = (%11_10 << 5) | $16
MIWRH     = (%11_10 << 5) | $17
MIRDL     = (%11_10 << 5) | $18
MIRDH     = (%11_10 << 5) | $19
              
' Bank 3
MAADR5    = (%11_11 << 5) | $00
MAADR6    = (%11_11 << 5) | $01
MAADR3    = (%11_11 << 5) | $02
MAADR4    = (%11_11 << 5) | $03
MAADR1    = (%11_11 << 5) | $04
MAADR2    = (%11_11 << 5) | $05
EBSTSD    = (%01_11 << 5) | $06
EBSTCON   = (%01_11 << 5) | $07
EBSTCSL   = (%01_11 << 5) | $08
EBSTCSH   = (%01_11 << 5) | $09
MISTAT    = (%11_11 << 5) | $0A
EREVID    = (%01_11 << 5) | $12
ECOCON    = (%01_11 << 5) | $15
EFLOCON   = (%01_11 << 5) | $17
EPAUSL    = (%01_11 << 5) | $18
EPAUSH    = (%01_11 << 5) | $19

' PHY registers

PHCON1    = $00
PHSTAT1   = $01
PHID1     = $02
PHID2     = $03
PHCON2    = $10
PHSTAT2   = $11
PHIE      = $12
PHIR      = $13
PHLCON    = $14

' Individual register bits

'EIE
RXERIE    = 1 << 0
TXERIE    = 1 << 1
TXIE      = 1 << 3
LINKIE    = 1 << 4
DMAIE     = 1 << 5
PKTIE     = 1 << 6
INTIE     = 1 << 7

'EIR
RXERIF    = 1 << 0
TXERIF    = 1 << 1
TXIF      = 1 << 3
LINKIF    = 1 << 4
DMAIF     = 1 << 5
PKTIF     = 1 << 6

'ESTAT
CLKRDY    = 1 << 0
TXABRT    = 1 << 1
RXBUSY    = 1 << 2
LATECOL   = 1 << 4
BUFER     = 1 << 6
INT       = 1 << 7

'ECON2
VRPS      = 1 << 3
PWRSV     = 1 << 5
PKTDEC    = 1 << 6
AUTOINC   = 1 << 7

'ECON1
BSEL0     = 1 << 0
BSEL1     = 1 << 1
RXEN      = 1 << 2
TXRTS     = 1 << 3
CSUMEN    = 1 << 4
DMAST     = 1 << 5
RXRST     = 1 << 6
TXRST     = 1 << 7

'ERXFCON
BCEN      = 1 << 0
MCEN      = 1 << 1
HTEN      = 1 << 2
MPEN      = 1 << 3
PMEN      = 1 << 4
CRCEN     = 1 << 5
ANDOR     = 1 << 6
UCEN      = 1 << 7

'MACON1
MARXEN    = 1 << 0
PASSALL   = 1 << 1
RXPAUS    = 1 << 2
TXPAUS    = 1 << 3

'MACON3 
FULDPX    = 1 << 0
FRMLNEN   = 1 << 1
HFRMEN    = 1 << 2
PHDREN    = 1 << 3
TXCRCEN   = 1 << 4
PADCFG0   = 1 << 5
PADCFG1   = 1 << 6
PADCFG2   = 1 << 7

'MACON4 
NOBKOFF   = 1 << 4
BPEN      = 1 << 5
DEFER     = 1 << 6

'MICMD
MIIRD     = 1 << 0
MIISCAN   = 1 << 1

'EBSTCON                       
BISTST    = 1 << 0
TME       = 1 << 1
TMSEL0    = 1 << 2
TMSEL1    = 1 << 3
PSEL      = 1 << 4
PSV0      = 1 << 5
PSV1      = 1 << 6
PSV2      = 1 << 7

'MISTAT 
BUSY      = 1 << 0
SCAN      = 1 << 1
NVALID    = 1 << 2

'EFLOCON
FCEN0     = 1 << 0
FCEN1     = 1 << 1
FULDPXS   = 1 << 2

'PHCON1
PDPXMD    = 1 << 8
PPWRSV    = 1 << 11
PLOOPBK   = 1 << 14
PRST      = 1 << 15

'PHSTAT1
JBSTAT    = 1 << 1
LLSTAT    = 1 << 2
PHDPX     = 1 << 11
PFDPX     = 1 << 12

'PHCON2
HDLDIS    = 1 << 8
JABBER    = 1 << 10
TXDIS     = 1 << 13
FRCLNK    = 1 << 14

'PHSTAT2
PLRITY    = 1 << 5
DPXSTAT   = 1 << 9
LSTAT     = 1 << 10
COLSTAT   = 1 << 11
RXSTAT    = 1 << 12
TXSTAT    = 1 << 13

'PHIE
PGEIE     = 1 << 1
PLNKIE    = 1 << 4

'PHIR
PGIF      = 1 << 2
PLNKIF    = 1 << 4

'PHLCON
STRCH     = 1 << 1
LFRQ_0    = 0 << 2
LFRQ_1    = 1 << 2
LFRQ_2    = 2 << 2
LBCFG_BIT = 4
LACFG_BIT = 8

'Nonzero reserved bits in PHLCON
PHLCON_RESERVED = $3000

'LED settings (for LACFG/LBCFG fields in PHLCON)
LED_TX          = 1
LED_RX          = 2
LED_COLLISION   = 3
LED_LINK        = 4
LED_DUPLEX      = 5
LED_TXRX        = 7
LED_ON          = 8
LED_OFF         = 9
LED_BLINK_FAST  = 10
LED_BLINK_SLOW  = 11
LED_LINK_RX     = 12
LED_LINK_TXRX   = 13
LED_DUPLEX_COLL = 14


'==============================================================================
' Protocol constants
'==============================================================================

' Ethernet frame types (EtherType)

ETHERTYPE_ARP   = $0806
ETHERTYPE_IPV4  = $0800

' ARP constants

ARP_HW_ETHERNET = $00010000
ARP_LENGTHS     = $06040000
ARP_REQUEST     = $00000001
ARP_REPLY       = $00000002

' IP constants

IP_VERSION      = 4
IP_HEADER_LEN   = 5    ' In 32-bit words
IP_PROTO_ICMP   = 1
IP_PROTO_TCP    = 6
IP_PROTO_UDP    = 17

' ICMP constants

ICMP_ECHO_REQUEST  = 8
ICMP_ECHO_REPLY    = 0


'==============================================================================
' Implementation-specific constants
'==============================================================================

' These constants represent values that are not intrinsic to the ENC28J60
' chip itself, but are constants specific to this driver implementation.

' According to Revision B5 errata 10, the transmitter may occasionally hang
' (TXRTS is never cleared) due to transmit errors, and the transmitter may
' need to be reset. However, in my experience, even this doesn't seem to be
' enough. If we are transmitting continuously, eventually the transmitter
' will hang even though TXERIF has never been set! To work around this, we
' eventually time out a transmit attempt if the TXRTS flag has been set for
' too many tx_poll attempts in a row.

TX_POLL_TIMEOUT = $1FF

' Maximum amount of data we have to buffer for one frame:
' 6-byte DA, 6-byte SA, 2-byte type/length, up to 1500 data
' and padding bytes, 4-byte FCS.

MAX_FRAME_LEN   = 1518

' Allocation for the chip's 8K SRAM buffer. We can partition the 8K any way we
' like. For the best performance, we should be able to transmit/receive and
' prepare to transmit/receive simultaneously. This means we need a transmit
' buffer large enough to store at least two full ethernet frames. For simplicity,
' we use a pure double-buffering scheme- so we have exactly two transmit buffers,
' each of which hold a single frame.
'
' It would be more efficient to treat the transmit buffer space as a continuous
' ring buffer, but that would require a lot of extra cog memory for the code and
' data necessary to track multiple frames that are all ready to transmit.
'
' All remaining memory is used for the receive buffer. The receive buffer is
' more important anyway, since it's what lets us avoid dropping packets even if
' they arrive while we were busy doing something else, like preparing to transmit.
' We always want the receive buffer to be larger than the transmit buffer.
'
' Note that transmitted packets include 8 bytes of extra control/status information.
' We add this to MAX_FRAME_LEN to calculate the actual amount of buffer space that's
' required.
'
' The start/end values are inclusive the bytes pointed to by 'start' and 'end'
' are both part of the buffer.
'
' Also note Rev B5 errata 3: We must place the receive buffer at offset zero.
'
' And Rev B5 errata 11: RX_BUF_END must always be odd.

MEM_SIZE        = 8192           
TX_BUF2_END     = MEM_SIZE - 1                            ' One 1528-byte TX buffer
TX_BUF2_START   = MEM_SIZE - (MAX_FRAME_LEN + 8) * 1
TX_BUF1_END     = TX_BUF2_START - 1                       ' Another 1528-byte TX buffer
TX_BUF1_START   = MEM_SIZE - (MAX_FRAME_LEN + 8) * 2
RX_BUF_END      = TX_BUF1_START - 1                       ' 5140-byte RX buffer
RX_BUF_START    = 0

' Default PHLCON value, without LED definitions.
' Enable pulse stretching, with the medium duration.

PHLCON_TEMPLATE = PHLCON_RESERVED | STRCH | LFRQ_0

' Default LED assignments:
'
'    - LED A shows link and receive activity
'    - LED B shows transmit activity

PHLCON_INIT     = PHLCON_TEMPLATE | (LED_LINK_RX << LACFG_BIT) | (LED_TX << LBCFG_BIT)


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
