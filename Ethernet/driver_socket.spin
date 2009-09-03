{{
  Ethernet TCP/IP Socket Layer Driver (IPv4)
  ------------------------------------------
  
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

CON
' ***************************************
' **      Versioning Information       **
' ***************************************
  version    = 2                ' major version
  release    = 5                ' minor version
  apiversion = 4                ' api compatibility version

' ***************************************
' **     User Definable Settings       **
' ***************************************
  sNumSockets     = 2           ' number of concurrent sockets (max of 255)
  rxbuffer_length = 256         ' socket receive buffer size (2, 4, 8, 16, 32, 64, 128 , ..., 65536)
  txbuffer_length = 256         ' socket transmit buffer size

' *** End of user definable settings, don't edit anything below this line!!!
' *** All IP/MAC settings are defined by calling the start(...) method

CON
' ***************************************
' **      Return Codes / Errors        **
' ***************************************

  RETBUFFEREMPTY  = -1          ' no data available
  RETBUFFERFULL   = -1          ' buffer full

  ERRGENERIC      = -1          ' generic errors
  
  ERR             = -100        ' error codes start at -500
  ERRBADHANDLE    = ERR - 1     ' bad socket handle
  ERROUTOFSOCKETS = ERR - 2     ' no free sockets available
  ERRSOCKETCLOSED = ERR - 3     ' socket closed, could not perform operation

OBJ
  nic : "driver_enc28j60"

  'ser : "SerialMirror"
  'stk : "Stack Length"

CON
' ***************************************
' **   Socket Constants and Offsets    **
' ***************************************
' The following is an 'array' that represents all the socket handle data (with respect to the remote host)
' longs first, then words, then bytes (for alignment)
'
'         4 bytes - (1 long ) my sequence number
'         4 bytes - (1 long ) my acknowledgement number
'         4 bytes - (1 long ) src ip
'         4 bytes - (1 long ) socket state timer
'         2 bytes - (1 word ) src port
'         2 bytes - (1 word ) dst port
'         2 bytes - (1 word ) last window
'         2 bytes - (1 word ) last transmitted packet length
'         6 bytes - (6 bytes) src mac address
'         1 byte  - (1 byte ) conn state
'         1 byte  - (1 byte ) handle index (MUST be the last item in the array)
' total: 32 bytes

  sSocketBytes = 32             ' MUST BE MULTIPLE OF 4 (long aligned) set this to total socket state data size

' Offsets for socket status arrays
  sMySeqNum  = 0
  sMyAckNum  = sMySeqNum+4
  sSrcIp     = sMyAckNum+4
  sTime      = sSrcIp+4
  sSrcPort   = sTime+4
  sDstPort   = sSrcPort+2
  sLastWin   = sDstPort+2
  sLastTxLen = sLastWin+2
  sSrcMac    = sLastTxLen+2
  sConState  = sSrcMac+6
  sSockIndex = sConState+1      ' sSockIndex MUST be the last item in the array, otherwise it won't work right

' Socket states (user should never touch these)
  SCLOSED          = 0          ' closed, handle not used
  SLISTEN          = 1          ' listening, in server mode
  SSYNSENT         = 2          ' SYN sent, server mode, waits for ACK
  SSYNSENTCL       = 3          ' SYN sent, client mode, waits for SYN+ACK
  SESTABLISHED     = 4          ' established connection (either SYN+ACK, or ACK+Data)
  SCLOSING         = 5          ' connection is being forced closed by code
  SCLOSING2        = 6          ' closing, we are waiting for a fin now
  SFORCECLOSE      = 7          ' force connection close (just RSTs, no waiting for FIN or anything)
  SCONNECTINGARP1  = 8          ' connecting, next step: send arp request
  SCONNECTINGARP2  = 9          ' connecting, next step: arp request sent, waiting for response
  SCONNECTINGARP2G = 10         ' connecting, next step: arp request sent, waiting for response [GATEWAY REQUEST]
  SCONNECTING      = 11         ' connecting, next step: got mac address, send SYN

' ***************************************
' **    Circular Buffer Constants      **
' ***************************************
  rxbuffer_mask = rxbuffer_length - 1
  txbuffer_mask = txbuffer_length - 1

' ***************************************
' **  TCP State Management Constants   **
' ***************************************
  TIMEOUTMS     = 500               ' (milliseconds) socket operation timeout, to prevent stalled states

  EPHPORTSTART  = 49152             ' ephemeral port start
  EPHPORTEND    = 65535             ' end

DAT
' ***************************************
' **          Global Variables         **
' ***************************************
  cog           long 0                                    ' cog index (for stopping / starting)
  stack         long 0[128]                               ' stack for new cog (currently ~74 longs, using 128 for expansion)

  mac_ptr       long 0                                    ' mac address pointer
  
  pkt           long 0                                    ' memory address of packet start

  pkt_id        long 0                                    ' packet fragmentation id
  pkt_isn       long 0                                    ' packet initial sequence number

  ip_ephport    word 0                                    ' packet ephemeral port number (49152 to 65535)

  pkt_count     byte 0                                    ' packet count
  
  lock_id       byte 0                                    ' socket handle lock

' ***************************************
' **        IP Address Defaults        **
' ***************************************
  ' NOTE: All of the MAC/IP variables here contain default values that will
  '       be used if override values are not provided as parameters in start().
                long                                      ' long alignment for addresses
  ip_addr       byte    10, 10, 1, 4                      ' device's ip address
  ip_subnet     byte    255, 255, 255, 0                  ' network subnet
  ip_gateway    byte    10, 10, 1, 254                    ' network gateway (router)
  ip_dns        byte    10, 10, 1, 254                    ' network dns 

' ***************************************
' **        Socket Data Arrays         **
' ***************************************
                long                                      ' long align the socket state data
  sSockets      byte      0[sSocketBytes * sNumSockets]   ' socket data array space (pre allocate)

' ***************************************
' **      Circular Buffer Arrays       **
' ***************************************
  rx_head       word      0[sNumSockets]                  ' rx head array
  rx_tail       word      0[sNumSockets]                  ' rx tail array
  tx_head       word      0[sNumSockets]                  ' tx head array
  tx_tail       word      0[sNumSockets]                  ' tx tail array

  tx_tailnew    word      0[sNumSockets]                  ' the new tx_tail value (unacked data)

  tx_buffer     byte      0[txbuffer_length * sNumSockets]  ' transmit buffer space

  rx_buffer     byte      0[rxbuffer_length * sNumSockets]  ' receive buffer space 

PUB start(cs, sck, si, so, int, xtalout, macptr, ipconfigptr) | socketIdx
'' Start the TCP/IP Stack (requires 2 cogs)
'' Only call this once, otherwise you will get conflicts
''   macptr      = HUB memory pointer (address) to 6 contiguous mac address bytes
''   ipconfigptr = HUB memory pointer (address) to ip configuration block (16 bytes)
''                 Must be in order: ip_addr, ip_subnet, ip_gateway, ip_dns

  stop
  'stk.Init(@stack, 128)

  ' zero socket data arrays (clean up any dead stuff from previous instance)
  bytefill(@sSockets, 0, constant(sSocketBytes * sNumSockets))

  ' reset buffer pointers, zeros a contigous set of bytes, starting at rx_head
  wordfill(@rx_head, 0, constant(sNumSockets * 4))

  ' setup pointer address values and indexing values
  repeat socketIdx from 0 to constant(sNumSockets - 1)
    BYTE[@sSockets][(socketIdx * sSocketBytes) + sSockIndex] := socketIdx       ' set socket indicies

  ' start new cog with tcp stack
  cog := cognew(engine(cs, sck, si, so, int, xtalout, macptr, ipconfigptr), @stack) + 1

PUB stop
'' Stop the driver

  if cog
    nic.stop                    ' stop nic driver (kills spi engine)
    cogstop(cog~ - 1)           ' stop the tcp engine
    lockret(lock_id)            ' return the lock to the lock pool

PRI engine(cs, sck, si, so, int, xtalout, macptr, ipconfigptr) | i

  lock_id := locknew

  ' Start the ENC28J60 driver in a new cog
  nic.start(cs, sck, si, so, int, xtalout, macptr)                              ' init the nic
  
  if ipconfigptr > -1                                                           ' init ip configuration
    bytemove(@ip_addr, ipconfigptr, 16)
  
  mac_ptr := nic.get_mac_pointer                                                ' get the local mac address pointer
    
  pkt := nic.get_packetpointer                                                  ' get the packet pointer 

  ip_ephport := EPHPORTSTART                                                    ' set initial ephemeral port number (might want to random seed this later)
  
  i := 0
  nic.banksel(nic#EPKTCNT)                                                      ' select packet count bank
  repeat
    pkt_count := nic.rd_cntlreg(nic#EPKTCNT)
    if pkt_count > 0
      service_packet                                                            ' handle packet
      nic.banksel(nic#EPKTCNT)                                                  ' re-select the packet count bank

    ++i
    if i > 10                                                                   ' perform send tick 
      tick_tcpsend                                                              '  occurs every 10 cycles, since incoming packets more important
      i := 0
      nic.banksel(nic#EPKTCNT)                                                  ' re-select the packet count bank

PRI service_packet

  ' lets process this frame
  nic.get_frame

  ' check for arp packet type (highest priority obviously)
  if BYTE[pkt][enetpacketType0] == $08 AND BYTE[pkt][enetpacketType1] == $06
    if BYTE[pkt][constant(arp_hwtype + 1)] == $01 AND BYTE[pkt][arp_prtype] == $08 AND BYTE[pkt][constant(arp_prtype + 1)] == $00 AND BYTE[pkt][arp_hwlen] == $06 AND BYTE[pkt][arp_prlen] == $04
      if BYTE[pkt][arp_tipaddr] == ip_addr[0] AND BYTE[pkt][constant(arp_tipaddr + 1)] == ip_addr[1] AND BYTE[pkt][constant(arp_tipaddr + 2)] == ip_addr[2] AND BYTE[pkt][constant(arp_tipaddr + 3)] == ip_addr[3]
        case BYTE[pkt][constant(arp_op + 1)]
          $01 : handle_arp
          $02 : handle_arpreply
        '++count_arp
  else
    if BYTE[pkt][enetpacketType0] == $08 AND BYTE[pkt][enetpacketType1] == $00
      if BYTE[pkt][ip_destaddr] == ip_addr[0] AND BYTE[pkt][constant(ip_destaddr + 1)] == ip_addr[1] AND BYTE[pkt][constant(ip_destaddr + 2)] == ip_addr[2] AND BYTE[pkt][constant(ip_destaddr + 3)] == ip_addr[3]
        case BYTE[pkt][ip_proto]
          'PROT_ICMP : 'handle_ping
                      'ser.str(stk.GetLength(0, 0))
                      'stk.GetLength(30, 19200)
                      '++count_ping
          PROT_TCP :  \handle_tcp                                               ' handles abort out of tcp handlers (no socket found)
                      '++count_tcp
          'PROT_UDP :  ++count_udp

' *******************************
' ** Protocol Receive Handlers **
' *******************************
PRI handle_arp | i
  nic.start_frame

  ' destination mac address
  repeat i from 0 to 5
    nic.wr_frame(BYTE[pkt][enetpacketSrc0 + i])

  ' source mac address
  repeat i from 0 to 5
    nic.wr_frame(BYTE[mac_ptr][i])

  nic.wr_frame($08)             ' arp packet
  nic.wr_frame($06)

  nic.wr_frame($00)             ' 10mb ethernet
  nic.wr_frame($01)

  nic.wr_frame($08)             ' ip proto
  nic.wr_frame($00)

  nic.wr_frame($06)             ' mac addr len
  nic.wr_frame($04)             ' proto addr len

  nic.wr_frame($00)             ' arp reply
  nic.wr_frame($02)

  ' write ethernet module mac address
  repeat i from 0 to 5
    nic.wr_frame(BYTE[mac_ptr][i])

  ' write ethernet module ip address
  repeat i from 0 to 3
    nic.wr_frame(ip_addr[i])

  ' write remote mac address
  repeat i from 0 to 5
    nic.wr_frame(BYTE[pkt][enetpacketSrc0 + i])

  ' write remote ip address
  repeat i from 0 to 3
    nic.wr_frame(BYTE[pkt][arp_sipaddr + i])

  return nic.send_frame

PRI handle_arpreply | handle, handle_addr, ip, found
  ' Gets arp reply if it is a response to an ip we have

  ip := (BYTE[pkt][constant(arp_sipaddr + 3)] << 24) + (BYTE[pkt][constant(arp_sipaddr + 2)] << 16) + (BYTE[pkt][constant(arp_sipaddr + 1)] << 8) + (BYTE[pkt][arp_sipaddr])

  found := false
  if ip == LONG[@ip_gateway]
    ' find a handle that wants gateway mac
    repeat handle from 0 to constant(sNumSockets - 1)
      handle_addr := @sSockets + (sSocketBytes * handle)
      if BYTE[handle_addr + sConState] == SCONNECTINGARP2G
        found := true
        quit
  else
    ' find the one that wants this arp
    repeat handle from 0 to constant(sNumSockets - 1)
      handle_addr := @sSockets + (sSocketBytes * handle)
      if BYTE[handle_addr + sConState] == SCONNECTINGARP2
        if LONG[handle_addr + sSrcIp] == ip
          found := true
          quit
          
  if found
    bytemove(handle_addr + sSrcMac, pkt + arp_shaddr, 6)
    BYTE[handle_addr + sConState] := SCONNECTING

'PRI handle_ping
  ' Not implemented yet (save on space!)
  
PRI handle_tcp | i, ptr, handle, handle_addr, srcip, dstport, srcport, datain_len, head
  ' Handles incoming TCP packets

  srcip := BYTE[pkt][ip_srcaddr] << 24 + BYTE[pkt][constant(ip_srcaddr + 1)] << 16 + BYTE[pkt][constant(ip_srcaddr + 2)] << 8 + BYTE[pkt][constant(ip_srcaddr + 3)]
  dstport := BYTE[pkt][TCP_destport] << 8 + BYTE[pkt][constant(TCP_destport + 1)]
  srcport := BYTE[pkt][TCP_srcport] << 8 + BYTE[pkt][constant(TCP_srcport + 1)]

  handle_addr := find_socket(srcip, dstport, srcport)   ' if no sockets avail, it will abort out of this function
  
  handle := BYTE[handle_addr + sSockIndex]

  ' at this point we assume we have an active socket, or a socket available to be used
  datain_len := ((BYTE[pkt][ip_pktlen] << 8) + BYTE[pkt][constant(ip_pktlen + 1)]) - ((BYTE[pkt][ip_vers_len] & $0F) * 4) - (((BYTE[pkt][TCP_hdrlen] & $F0) >> 4) * 4)

  if (BYTE[handle_addr + sConState] == SSYNSENT OR BYTE[handle_addr + sConState] == SESTABLISHED) AND (BYTE[pkt][TCP_hdrflags] & TCP_ACK) > 0 AND datain_len > 0
    ' ACK, without SYN, with data

    ' set socket state, established session
    BYTE[handle_addr + sConState] := SESTABLISHED
    
    i := BYTE[pkt][constant(TCP_seqnum + 3)] << 24 + BYTE[pkt][constant(TCP_seqnum + 2)] << 16 + BYTE[pkt][constant(TCP_seqnum + 1)] << 8 + BYTE[pkt][TCP_seqnum]
    if LONG[handle_addr + sMyAckNum] == i
      if datain_len =< (rxbuffer_mask - ((rx_head[handle] - rx_tail[handle]) & rxbuffer_mask))
        ' we have buffer space
        ptr := @rx_buffer + (handle * rxbuffer_length)
        if (datain_len + rx_head[handle]) > rxbuffer_length
          bytemove(ptr + rx_head[handle], @BYTE[pkt][TCP_data], rxbuffer_length - rx_head[handle])
          bytemove(ptr, @BYTE[pkt][TCP_data] + (rxbuffer_length - rx_head[handle]), datain_len - (rxbuffer_length - rx_head[handle]))
        else
          bytemove(ptr + rx_head[handle], @BYTE[pkt][TCP_data], datain_len)
        rx_head[handle] := (rx_head[handle] + datain_len) & rxbuffer_mask
      else
        datain_len := 0  

    else
      ' we had a bad ack number, meaning lost or out of order packet
      ' we have to wait for the remote host to retransmit in order
      datain_len := 0
     
    ' recalculate ack number
    LONG[handle_addr + sMyAckNum] := conv_endianlong(conv_endianlong(LONG[handle_addr + sMyAckNum]) + datain_len)

    ' ACK response
    build_ipheaderskeleton(handle_addr)
    build_tcpskeleton(handle_addr, TCP_ACK)
    send_tcpfinal(handle_addr, 0)

  elseif (BYTE[handle_addr + sConState] == SSYNSENTCL) AND (BYTE[pkt][TCP_hdrflags] & TCP_SYN) > 0 AND (BYTE[pkt][TCP_hdrflags] & TCP_ACK) > 0
    ' We got a server response, so we ACK it

    bytemove(handle_addr + sMySeqNum, pkt + TCP_acknum, 4)
    bytemove(handle_addr + sMyAckNum, pkt + TCP_seqnum, 4)
    
    LONG[handle_addr + sMyAckNum] := conv_endianlong(conv_endianlong(LONG[handle_addr + sMyAckNum]) + 1)

    ' ACK response
    build_ipheaderskeleton(handle_addr)
    build_tcpskeleton(handle_addr, TCP_ACK)
    send_tcpfinal(handle_addr, 0)

    ' set socket state, established session
    BYTE[handle_addr + sConState] := SESTABLISHED
  
  elseif (BYTE[handle_addr + sConState] == SLISTEN) AND (BYTE[pkt][TCP_hdrflags] & TCP_SYN) > 0
    ' Reply to SYN with SYN + ACK

    ' copy mac address so we don't have to keep an ARP table
    bytemove(handle_addr + sSrcMac, pkt + enetpacketSrc0, 6)

    ' copy ip, port data
    bytemove(handle_addr + sSrcIp, pkt + ip_srcaddr, 4)
    bytemove(handle_addr + sSrcPort, pkt + TCP_srcport, 2)
    bytemove(handle_addr + sDstPort, pkt + TCP_destport, 2)

    ' get updated ack numbers
    bytemove(handle_addr + sMyAckNum, pkt + TCP_seqnum, 4)

    LONG[handle_addr + sMyAckNum] := conv_endianlong(conv_endianlong(LONG[handle_addr + sMyAckNum]) + 1)
    LONG[handle_addr + sMySeqNum] := conv_endianlong(++pkt_isn)               ' Initial seq num (random)

    build_ipheaderskeleton(handle_addr)
    build_tcpskeleton(handle_addr, constant(TCP_SYN | TCP_ACK))
    send_tcpfinal(handle_addr, 0)      

    ' incremement the sequence number for the next packet (it will be for an established connection)                                          
    LONG[handle_addr + sMySeqNum] := conv_endianlong(conv_endianlong(LONG[handle_addr + sMySeqNum]) + 1)

    ' set socket state, waiting for establish
    BYTE[handle_addr + sConState] := SSYNSENT
   
  elseif (BYTE[handle_addr + sConState] == SESTABLISHED OR BYTE[handle_addr + sConState] == SCLOSING2) AND (BYTE[pkt][TCP_hdrflags] & TCP_FIN) > 0
    ' Reply to FIN with RST

    ' get updated sequence and ack numbers (gaurantee we have correct ones to kill connection with)
    bytemove(handle_addr + sMySeqNum, pkt + TCP_acknum, 4)
    bytemove(handle_addr + sMyAckNum, pkt + TCP_seqnum, 4)
                                              
    'LONG[handle_addr + sMyAckNum] := conv_endianlong(conv_endianlong(LONG[handle_addr + sMyAckNum]) + 1)

    build_ipheaderskeleton(handle_addr)
    build_tcpskeleton(handle_addr, TCP_RST)
    send_tcpfinal(handle_addr, 0)

    ' set socket state, now free
    BYTE[handle_addr + sConState] := SCLOSED
    return

  {elseif (BYTE[handle_addr + sConState] == SCLOSING2) AND (BYTE[pkt][TCP_hdrflags] & TCP_ACK) > 0
    ' the other side ACK'd our FIN, so let's just reset instead of negotiating another graceful FIN

    ' get updated sequence and ack numbers (gaurantee we have correct ones to kill connection with)
    bytemove(handle_addr + sMySeqNum, pkt + TCP_acknum, 4)
    bytemove(handle_addr + sMyAckNum, pkt + TCP_seqnum, 4)
                                              
    'LONG[handle_addr + sMyAckNum] := conv_endianlong(conv_endianlong(LONG[handle_addr + sMyAckNum]) + 1)

    build_ipheaderskeleton(handle_addr)
    build_tcpskeleton(handle_addr, TCP_RST)
    send_tcpfinal(handle_addr, 0)

    ' set socket state, now free
    BYTE[handle_addr + sConState] := SCLOSED}
    
  elseif (BYTE[handle_addr + sConState] == SSYNSENT) AND (BYTE[pkt][TCP_hdrflags] & TCP_ACK) > 0
    ' if just an ack, and we sent a syn before, then it's established
    ' this just gives us the ability to send on connect
    BYTE[handle_addr + sConState] := SESTABLISHED
  
  elseif (BYTE[pkt][TCP_hdrflags] & TCP_RST) > 0
    ' Reset, reset states
    BYTE[handle_addr + sConState] := SCLOSED
    return

  if BYTE[pkt][TCP_hdrflags] & TCP_ACK > 0
    ' check to see if our last sent data has been ack'd
    i := BYTE[pkt][TCP_acknum] << 24 + BYTE[pkt][constant(TCP_acknum + 1)] << 16 + BYTE[pkt][constant(TCP_acknum + 2)] << 8 + BYTE[pkt][constant(TCP_acknum + 3)]
    if i == (conv_endianlong(LONG[handle_addr + sMySeqNum]) + WORD[handle_addr + sLastTxLen])
      ' we received an ack for our last sent packet, so we update our sequence number and buffer pointers
      LONG[handle_addr + sMySeqNum] := conv_endianlong(conv_endianlong(LONG[handle_addr + sMySeqNum]) + WORD[handle_addr + sLastTxLen])
      tx_tail[handle] := tx_tailnew[handle]
      WORD[handle_addr + sLastTxLen] := 0
        
      tcpsend(handle)

PRI build_ipheaderskeleton(handle_addr) | hdrlen, hdr_chksum
  
  bytemove(pkt + ip_destaddr, handle_addr + sSrcIp, 4)                          ' Set destination address

  bytemove(pkt + ip_srcaddr, @ip_addr, 4)                                       ' Set source address

  bytemove(pkt + enetpacketDest0, handle_addr + sSrcMac, 6)                     ' Set destination mac address

  bytemove(pkt + enetpacketSrc0, mac_ptr, 6)                                    ' Set source mac address

  BYTE[pkt][enetpacketType0] := $08
  BYTE[pkt][constant(enetpacketType0 + 1)] := $00
  
  BYTE[pkt][ip_vers_len] := $45
  BYTE[pkt][ip_tos] := $00

  ++pkt_id
  
  BYTE[pkt][ip_id] := pkt_id >> 8                                               ' Used for fragmentation
  BYTE[pkt][constant(ip_id + 1)] := pkt_id

  BYTE[pkt][ip_frag_offset] := $40                                              ' Don't fragment
  BYTE[pkt][constant(ip_frag_offset + 1)] := 0
  
  BYTE[pkt][ip_ttl] := $80                                                      ' TTL = 128

  BYTE[pkt][ip_proto] := $06                                                    ' TCP protocol

PRI build_tcpskeleton(handle_addr, flags) | handle, size

  bytemove(pkt + TCP_srcport, handle_addr + sDstPort, 2)                        ' Source port
  bytemove(pkt + TCP_destport, handle_addr + sSrcPort, 2)                       ' Destination port

  bytemove(pkt + TCP_seqnum, handle_addr + sMySeqNum, 4)                        ' Seq Num
  bytemove(pkt + TCP_acknum, handle_addr + sMyAckNum, 4)                        ' Ack Num

  BYTE[pkt][TCP_hdrlen] := $50                                                  ' Header length
  
  BYTE[pkt][TCP_hdrflags] := flags                                              ' TCP state flags

  ' we have to recalculate the window size often otherwise our stack
  ' might explode from too much data :(
  handle := BYTE[handle_addr + sSockIndex]
  size := (rxbuffer_mask - ((rx_head[handle] - rx_tail[handle]) & rxbuffer_mask))
  WORD[handle_addr + sLastWin] := size

  BYTE[pkt][TCP_window] := (size & $FF00) >> 8
  BYTE[pkt][constant(TCP_window + 1)] := size & $FF
  
  'BYTE[pkt][TCP_window] := constant((window_size & $FF00) >> 8)              ' Window size (max data that can be received before ACK must be sent)
  'BYTE[pkt][constant(TCP_window + 1)] := constant(window_size & $FF)         '  we use our buffer_length to ensure our buffer won't get overloaded
                                                                                '  may cause slowness so some people may want to use $FFFF on high latency networks
  
PRI send_tcpfinal(handle_addr, datalen) | i, tcplen, hdrlen, hdr_chksum

  'LONG[handle_addr + sMySeqNum] := conv_endianlong(conv_endianlong(LONG[handle_addr + sMySeqNum]) + datalen)               ' update running sequence number

  tcplen := 40 + datalen                                                        ' real length = data + headers

  BYTE[pkt][ip_pktlen] := tcplen >> 8
  BYTE[pkt][constant(ip_pktlen + 1)] := tcplen

  ' calc ip header checksum
  BYTE[pkt][ip_hdr_cksum] := $00
  BYTE[pkt][constant(ip_hdr_cksum + 1)] := $00
  hdrlen := (BYTE[pkt][ip_vers_len] & $0F) * 4
  hdr_chksum := calc_chksum(@BYTE[pkt][ip_vers_len], hdrlen)  
  BYTE[pkt][ip_hdr_cksum] := hdr_chksum >> 8
  BYTE[pkt][constant(ip_hdr_cksum + 1)] := hdr_chksum

  ' calc checksum
  BYTE[pkt][TCP_cksum] := $00
  BYTE[pkt][constant(TCP_cksum + 1)] := $00
  hdr_chksum := nic.chksum_add(@BYTE[pkt][ip_srcaddr], 8)
  hdr_chksum += BYTE[pkt][ip_proto]
  i := tcplen - ((BYTE[pkt][ip_vers_len] & $0F) * 4)
  hdr_chksum += i
  hdr_chksum += nic.chksum_add(@BYTE[pkt][TCP_srcport], i)
  hdr_chksum := calc_chksumfinal(hdr_chksum)
  BYTE[pkt][TCP_cksum] := hdr_chksum >> 8
  BYTE[pkt][constant(TCP_cksum + 1)] := hdr_chksum

  tcplen += 14
  if tcplen < 60
    tcplen := 60

  ' protect from buffer overrun
  if tcplen => nic#TX_BUFFER_SIZE
    return
    
  ' send the packet
  nic.start_frame
  
  nic.wr_block(pkt, tcplen)

  {repeat i from 0 to tcplen - 1
    nic.wr_frame(BYTE[pkt][i])}

  ' send the packet
  nic.send_frame

  LONG[handle_addr + sTime] := cnt                      ' update last sent time (for timeout detection) 

PRI find_socket(srcip, dstport, srcport) | handle, free_handle, handle_addr
  ' Search for socket, matches ip address, port states
  ' Returns handle address (start memory location of socket)
  '  If no matches, will abort with -1
  '  If supplied with srcip = 0 then will return free unused handle, aborts with -1 if none avail
  
  free_handle := -1
  repeat handle from 0 to constant(sNumSockets - 1)
    handle_addr := @sSockets + (sSocketBytes * handle)   ' generate handle address (mapped to memory)
    if BYTE[handle_addr + sConState] <> SCLOSED
      if (LONG[handle_addr + sSrcIp] == 0) OR (LONG[handle_addr + sSrcIp] == conv_endianlong(srcip))
        ' ip match, ip socket srcip = 0, then will try to match dst port (find listening socket)
          if (WORD[handle_addr + sDstPort] == conv_endianword(dstport)) AND (WORD[handle_addr + sSrcPort] == 0 OR WORD[handle_addr + sSrcPort] == conv_endianword(srcport))
            ' port match, will match port, if srcport = 0 then will match dstport only (find listening socket)
            return handle_addr
    elseif srcip == 0
      ' we only return a free handle if we are searching for srcip = 0 (just looking for free handle)
      free_handle := handle_addr     ' we found a free handle, may need this later
      
  if free_handle <> -1
    return free_handle 
  else
    abort -1

' ******************************
' ** Transmit Buffer Handlers **
' ******************************
PRI tcpsend(handle) | handle_addr, state, ptr, len
  ' Check buffers for data to send (called in main loop)

  handle_addr := @sSockets + (sSocketBytes * handle)
  state := BYTE[handle_addr + sConState]
  if state == SESTABLISHED OR state == SCLOSING
    if tx_tail[handle] <> tx_head[handle]
      ' we have data to send, so send it!
      ptr := @tx_buffer + (handle * txbuffer_length)
      len := (tx_head[handle] - tx_tail[handle]) & txbuffer_mask
      if (len + tx_tail[handle]) > txbuffer_length
        bytemove(@BYTE[pkt][TCP_data], ptr + tx_tail[handle], txbuffer_length - tx_tail[handle])
        bytemove(@BYTE[pkt][TCP_data] + (txbuffer_length - tx_tail[handle]), ptr, len - (txbuffer_length - tx_tail[handle]))
      else
        bytemove(@BYTE[pkt][TCP_data], ptr + tx_tail[handle], len)
      tx_tailnew[handle] := (tx_tail[handle] + len) & txbuffer_mask

      WORD[handle_addr + sLastTxLen] := len 
   
      build_ipheaderskeleton(handle_addr)
      build_tcpskeleton(handle_addr, TCP_ACK {constant(TCP_ACK | TCP_PSH)})
      send_tcpfinal(handle_addr, len)

      send_tcpfinal(handle_addr, 0)                     ' send an empty packet to force the other side to ACK (hack to get around delayed acks)
   
PRI tick_tcpsend | handle, handle_addr, state, len

  repeat handle from 0 to constant(sNumSockets - 1)
    handle_addr := @sSockets + (sSocketBytes * handle)
    state := BYTE[handle_addr + sConState]

    if state == SESTABLISHED OR state == SCLOSING
      len := (rxbuffer_mask - ((rx_head[handle] - rx_tail[handle]) & rxbuffer_mask))
      if WORD[handle_addr + sLastWin] <> len AND len => constant(rxbuffer_length / 2)
        ' update window size
        build_ipheaderskeleton(handle_addr)
        build_tcpskeleton(handle_addr, TCP_ACK)
        send_tcpfinal(handle_addr, 0)

      if ((cnt - LONG[handle_addr + sTime]) / (clkfreq / 1000) > TIMEOUTMS) OR WORD[handle_addr + sLastTxLen] == 0
        ' send new data OR retransmit our last packet since the other side seems to have lost it
        ' the remote host will respond with another dup ack, and we will get back on track (hopefully)
        tcpsend(handle)  
    
    if state == SCLOSING                                         
     
      build_ipheaderskeleton(handle_addr)
      build_tcpskeleton(handle_addr, constant(TCP_ACK | TCP_FIN))
      send_tcpfinal(handle_addr, 0)
     
      ' we now wait for the other side to terminate
      BYTE[handle_addr + sConState] := SCLOSING2
     
    elseif state == SCONNECTINGARP1
      ' We need to send an arp request
     
      arp_request_checkgateway(handle_addr)
     
    elseif state == SCONNECTING
      ' Yea! We got an arp response previously, so now we can send the SYN
     
      LONG[handle_addr + sMySeqNum] := conv_endianlong(++pkt_isn)        
      LONG[handle_addr + sMyAckNum] := 0
       
      build_ipheaderskeleton(handle_addr)
      build_tcpskeleton(handle_addr, TCP_SYN)
      send_tcpfinal(handle_addr, 0)
     
      BYTE[handle_addr + sConState] := SSYNSENTCL
     
    elseif (state == SFORCECLOSE) OR ((state == SCLOSING2 OR state == SSYNSENT) AND ((cnt - LONG[handle_addr + sTime]) / (clkfreq / 1000) > TIMEOUTMS))
      ' Force close (send RST, and say the socket is closed!)
      
      ' This is triggered when any of the following happens:
      '  1 - we don't get a response to our SSYNSENT state
      '  2 - we get stuck in the SSCLOSING2 state
     
      build_ipheaderskeleton(handle_addr)
      build_tcpskeleton(handle_addr, TCP_RST)
      send_tcpfinal(handle_addr, 0)
     
      BYTE[handle_addr + sConState] := SCLOSED

PRI arp_request_checkgateway(handle_addr) | ip_ptr

  ip_ptr := handle_addr + sSrcIp
  
  if (BYTE[ip_ptr] & ip_subnet[0]) == (ip_addr[0] & ip_subnet[0]) AND (BYTE[ip_ptr + 1] & ip_subnet[1]) == (ip_addr[1] & ip_subnet[1]) AND (BYTE[ip_ptr + 2] & ip_subnet[2]) == (ip_addr[2] & ip_subnet[2]) AND (BYTE[ip_ptr + 3] & ip_subnet[3]) == (ip_addr[3] & ip_subnet[3])   
    arp_request(conv_endianlong(LONG[ip_ptr]))
    BYTE[handle_addr + sConState] := SCONNECTINGARP2
  else
    arp_request(conv_endianlong(LONG[@ip_gateway]))
    BYTE[handle_addr + sConState] := SCONNECTINGARP2G   
  
PRI arp_request(ip) | i
  nic.start_frame

  ' destination mac address (broadcast mac)
  repeat i from 0 to 5
    nic.wr_frame($FF)

  ' source mac address (this device)
  repeat i from 0 to 5
    nic.wr_frame(BYTE[mac_ptr][i])

  nic.wr_frame($08)             ' arp packet
  nic.wr_frame($06)

  nic.wr_frame($00)             ' 10mb ethernet
  nic.wr_frame($01)

  nic.wr_frame($08)             ' ip proto
  nic.wr_frame($00)

  nic.wr_frame($06)             ' mac addr len
  nic.wr_frame($04)             ' proto addr len

  nic.wr_frame($00)             ' arp request
  nic.wr_frame($01)

  ' source mac address (this device)
  repeat i from 0 to 5
    nic.wr_frame(BYTE[mac_ptr][i])

  ' source ip address (this device)
  repeat i from 0 to 3
    nic.wr_frame(ip_addr[i])

  ' unknown mac address area
  repeat i from 0 to 5
    nic.wr_frame($00)

  ' figure out if we need router arp request or host arp request
  ' this means some subnet masking

  ' dest ip address
  repeat i from 3 to 0
    nic.wr_frame(ip.byte[i])

  ' send the request
  return nic.send_frame
  
' *******************************
' ** IP Packet Helpers (Calcs) **
' *******************************    
PRI calc_chksum(packet, hdrlen) : chksum
  ' Calculates IP checksums
  ' packet = pointer to IP packet
  ' returns: chksum
  ' http://www.geocities.com/SiliconValley/2072/bit33.txt
  'chksum := calc_chksumhalf(packet, hdrlen)
  chksum := nic.chksum_add(packet, hdrlen)
  chksum := calc_chksumfinal(chksum)

PRI calc_chksumfinal(chksumin) : chksum
  ' Performs the final part of checksums
  chksum := (chksumin >> 16) + (chksumin & $FFFF)
  chksum := (!chksum) & $FFFF
  
{PRI calc_chksumhalf(packet, hdrlen) : chksum
  ' Calculates checksum without doing the final stage of calculations
  chksum := 0
  repeat while hdrlen > 1
    chksum += (BYTE[packet++] << 8) + BYTE[packet++]
    chksum := (chksum >> 16) + (chksum & $FFFF)
    hdrlen -= 2
  if hdrlen > 0              
    chksum += BYTE[packet] << 8}

' ***************************
' ** Memory Access Helpers **
' ***************************    
PRI conv_endianlong(in)
  'return (in << 24) + ((in & $FF00) << 8) + ((in & $FF0000) >> 8) + (in >> 24)  ' we can sometimes get away with shifting without masking, since shifts kill extra bits anyways
  return (in.byte[0] << 24) + (in.byte[1] << 16) + (in.byte[2] << 8) + (in.byte[3])
  
PRI conv_endianword(in)
  'return ((in & $FF) << 8) + ((in & $FF00) >> 8)
  return (in.byte[0] << 8) + (in.byte[1])

PRI _handleCheck(handle)
' Checks to see if a handle index is valid
' Aborts if the handle is invalid
  if handle < 0 OR handle > constant(sNumSockets - 1)
    abort ERRBADHANDLE

' ************************************
' ** Public Accessors (Thread Safe) **
' ************************************
PUB listen(port) | handle_addr, handle
'' Sets up a socket for listening on a port
''   port = port number to listen on
'' Returns handle if available, ERROUTOFSOCKETS if none available
'' Nonblocking

  repeat while lockset(lock_id)

  ' just find any avail closed socket
  handle_addr := \find_socket(0, 0, 0)

  if handle_addr < 0
    lockclr(lock_id)
    abort ERROUTOFSOCKETS

  handle := BYTE[handle_addr + sSockIndex]

  bytefill(handle_addr, 0, sSockIndex)                  ' clean socket state data, up to the socket index since this must stay
                                                        ' assumes socket index is last part of the array

  WORD[handle_addr + sSrcPort] := 0                     ' no source port yet
  WORD[handle_addr + sDstPort] := conv_endianword(port) ' we do have a dest port though

  WORD[handle_addr + sLastWin] := rxbuffer_length

  tx_head[handle] := 0
  tx_tail[handle] := 0
  tx_tailnew[handle] := 0
  rx_head[handle] := 0
  rx_tail[handle] := 0

  ' it's now listening
  BYTE[handle_addr + sConState] := SLISTEN

  lockclr(lock_id)

  return handle                 'BYTE[handle_addr + sSockIndex] 

PUB connect(ipaddr, remoteport) | handle_addr, handle
'' Connect to remote host
''   ipaddr     = ipv4 address packed into a long (ie: 1.2.3.4 => $01_02_03_04)
''   remoteport = port number to connect to
'' Returns handle to new socket, ERROUTOFSOCKETS if no socket available
'' Nonblocking

  repeat while lockset(lock_id)

  ' just find any avail closed socket
  handle_addr := \find_socket(0, 0, 0)

  if handle_addr < 0
    lockclr(lock_id)
    abort ERROUTOFSOCKETS

  handle := BYTE[handle_addr + sSockIndex]

  bytefill(handle_addr, 0, sSockIndex)                  ' clean socket state data, up to the socket index since this must stay
                                                        ' assumes socket index is last part of the array

  if(ip_ephport => EPHPORTEND)                          ' constrain ephport to specified range
    ip_ephport := EPHPORTSTART
  
  ' copy in ip, port data (with respect to the remote host, since we use same code as server)
  LONG[handle_addr + sSrcIp] := conv_endianlong(ipaddr)
  WORD[handle_addr + sSrcPort] := conv_endianword(remoteport)
  WORD[handle_addr + sDstPort] := conv_endianword(ip_ephport++)

  WORD[handle_addr + sLastWin] := rxbuffer_length

  tx_head[handle] := 0
  tx_tail[handle] := 0
  tx_tailnew[handle] := 0
  rx_head[handle] := 0
  rx_tail[handle] := 0

  BYTE[handle_addr + sConState] := SCONNECTINGARP1

  lockclr(lock_id)
  
  return handle                 'BYTE[handle_addr + sSockIndex]

PUB close(handle) | handle_addr, state
'' Closes a connection

  _handleCheck(handle)

  handle_addr := @sSockets + (sSocketBytes * handle)
  state := BYTE[handle_addr + sConState]

  if state == SESTABLISHED
    ' try to gracefully close the connection
    BYTE[handle_addr + sConState] := SCLOSING
  elseif state <> SCLOSING AND state <> SCLOSING2
    ' we only do an ungraceful close if we are not in ESTABLISHED, CLOSING, or CLOSING2
    BYTE[handle_addr + sConState] := SCLOSED

  {' wait a bit for the connection to close
  ' if we get no response from remote host then we just RST
  t := cnt
  repeat until (BYTE[handle_addr + sConState] == SCLOSED) or (cnt - t) / (clkfreq / 1000) > TIMEOUTMS
  if BYTE[handle_addr + sConState] <> SCLOSED
    ' if we haven't closed by now then we will force close via RST
    BYTE[handle_addr + sConState] := SFORCECLOSE}

PUB isConnected(handle) | handle_addr
'' Returns true if the socket is connected, false otherwise

  _handleCheck(handle)

  handle_addr := @sSockets + (sSocketBytes * handle)  
  return (BYTE[handle_addr + sConState] == SESTABLISHED)  

PUB isValidHandle(handle) | handle_addr
'' Checks to see if the handle is valid, handles will become invalid once they are used
'' In other words, a closed listening socket is now invalid, etc

  {if handle < 0 OR handle > constant(sNumSockets - 1)
    ' obviously the handle index is out of range, so it's not valid!
    return false}

  if \_handleCheck(handle) < 0
    return false

  handle_addr := @sSockets + (sSocketBytes * handle)
  return (BYTE[handle_addr + sConState] <> SCLOSED)

PUB readDataNonBlocking(handle, ptr, maxlen) | len, rxptr
'' Reads bytes from the socket
'' Returns number of read bytes
'' Not blocking (returns RETBUFFEREMPTY if no data)

  _handleCheck(handle)

  if rx_tail[handle] == rx_head[handle]
    return RETBUFFEREMPTY

  len := (rx_head[handle] - rx_tail[handle]) & rxbuffer_mask
  if maxlen < len
    len := maxlen

  rxptr := @rx_buffer + (handle * rxbuffer_length)
  
  if (len + rx_tail[handle]) > rxbuffer_length
    bytemove(ptr, rxptr + rx_tail[handle], rxbuffer_length - rx_tail[handle])
    bytemove(ptr + (rxbuffer_length - rx_tail[handle]), rxptr, len - (rxbuffer_length - rx_tail[handle]))
  else
    bytemove(ptr, rxptr + rx_tail[handle], len)

  rx_tail[handle] := (rx_tail[handle] + len) & rxbuffer_mask

  return len  

PUB readData(handle, ptr, maxlen) : len
'' Reads bytes from the socket
'' Returns the number of read bytes
'' Will block until data is received

  _handleCheck(handle)

  repeat while (len := readDataNonBlocking(handle, ptr, maxlen)) < 0
    ifnot isConnected(handle)
      abort ERRSOCKETCLOSED

PUB readByteNonBlocking(handle) : rxbyte | ptr
'' Read a byte from the specified socket
'' Will not block (returns RETBUFFEREMPTY if no byte avail)

  _handleCheck(handle)

  rxbyte := RETBUFFEREMPTY
  if rx_tail[handle] <> rx_head[handle]
    ptr := @rx_buffer + (handle * rxbuffer_length)
    rxbyte := BYTE[ptr][rx_tail[handle]]
    rx_tail[handle] := (rx_tail[handle] + 1) & rxbuffer_mask
    
PUB readByte(handle) : rxbyte | ptr
'' Read a byte from the specified socket
'' Will block until a byte is received

  _handleCheck(handle)

  repeat while (rxbyte := readByteNonBlocking(handle)) < 0
    ifnot isConnected(handle)
      abort ERRSOCKETCLOSED

PUB writeDataNonBlocking(handle, ptr, len) | txptr
'' Writes bytes to the socket
'' Will not write anything unless your data fits in the buffer
'' Non blocking (returns RETBUFFERFULL if can't fit data)

  _handleCheck(handle)

  if (txbuffer_mask - ((tx_head[handle] - tx_tail[handle]) & txbuffer_mask)) < len
    return RETBUFFERFULL

  txptr := @tx_buffer + (handle * txbuffer_length)
  
  if (len + tx_head[handle]) > txbuffer_length
    bytemove(txptr + tx_head[handle], ptr, txbuffer_length - tx_head[handle])
    bytemove(txptr, ptr + (txbuffer_length - tx_head[handle]), len - (txbuffer_length - tx_head[handle]))
  else
    bytemove(txptr + tx_head[handle], ptr, len)

  tx_head[handle] := (tx_head[handle] + len) & txbuffer_mask

  return len

PUB writeData(handle, ptr, len)
'' Writes data to the specified socket
'' Will block until all data is queued to be sent

  _handleCheck(handle)

  repeat while len > constant(txbuffer_length - 1)
    repeat while writeDataNonBlocking(handle, ptr, constant(txbuffer_length - 1)) < 0
      ifnot isConnected(handle)
        abort ERRSOCKETCLOSED
    len -= constant(txbuffer_length - 1)
    ptr += constant(txbuffer_length - 1)

  repeat while writeDataNonBlocking(handle, ptr, len) < 0
    ifnot isConnected(handle)
      abort ERRSOCKETCLOSED

PUB writeByteNonBlocking(handle, txbyte) | ptr
'' Writes a byte to the specified socket
'' Will not block (returns RETBUFFERFULL if no buffer space available)

  _handleCheck(handle)

  ifnot (tx_tail[handle] <> (tx_head[handle] + 1) & txbuffer_mask)
    return RETBUFFERFULL

  ptr := @tx_buffer + (handle * txbuffer_length)  
  BYTE[ptr][tx_head[handle]] := txbyte
  tx_head[handle] := (tx_head[handle] + 1) & txbuffer_mask

  return txbyte

PUB writeByte(handle, txbyte)
'' Write a byte to the specified socket
'' Will block until space is available for byte to be sent 

  _handleCheck(handle)

  repeat while writeByteNonBlocking(handle, txbyte) < 0
    ifnot isConnected(handle)
      abort ERRSOCKETCLOSED

PUB resetBuffers(handle)
'' Resets send/receive buffers for the specified socket

  _handleCheck(handle)

  rx_tail[handle] := rx_head[handle]
  tx_head[handle] := tx_tail[handle]

PUB flush(handle)
'' Flushes the send buffer (waits till the buffer is empty)
'' Will block until all tx data is sent

  _handleCheck(handle)

  repeat while isConnected(handle) AND tx_tail[handle] <> tx_head[handle]

PUB getSocketState(handle) | handle_addr
'' Gets the socket state (internal state numbers)
'' You can include driver_socket in any object and use the S... state constants for comparison

  _handleCheck(handle)

  handle_addr := @sSockets + (sSocketBytes * handle)
  return BYTE[handle_addr + sConState]

PUB getReceiveBufferCount(handle)
'' Returns the number of bytes in the receive buffer

  _handleCheck(handle)

  return (rx_head[handle] - rx_tail[handle]) & rxbuffer_mask 

CON
  '******************************************************************
  '*      TCP Flags
  '******************************************************************
  TCP_FIN = 1
  TCP_SYN = 2
  TCP_RST = 4
  TCP_PSH = 8
  TCP_ACK = 16
  TCP_URG = 32
  TCP_ECE = 64
  TCP_CWR = 128
  '******************************************************************
  '*      Ethernet Header Layout
  '******************************************************************                
  enetpacketDest0 = $00  'destination mac address
  enetpacketDest1 = $01
  enetpacketDest2 = $02
  enetpacketDest3 = $03
  enetpacketDest4 = $04
  enetpacketDest5 = $05
  enetpacketSrc0 = $06  'source mac address
  enetpacketSrc1 = $07
  enetpacketSrc2 = $08
  enetpacketSrc3 = $09
  enetpacketSrc4 = $0A
  enetpacketSrc5 = $0B
  enetpacketType0 = $0C  'type/length field
  enetpacketType1 = $0D
  enetpacketData = $0E  'IP data area begins here
  '******************************************************************
  '*      ARP Layout
  '******************************************************************
  arp_hwtype = $0E
  arp_prtype = $10
  arp_hwlen = $12
  arp_prlen = $13
  arp_op = $14
  arp_shaddr = $16   'arp source mac address
  arp_sipaddr = $1C   'arp source ip address
  arp_thaddr = $20   'arp target mac address
  arp_tipaddr = $26   'arp target ip address
  '******************************************************************
  '*      IP Header Layout
  '******************************************************************
  ip_vers_len = $0E       'IP version and header length 1a19
  ip_tos = $0F    'IP type of service
  ip_pktlen = $10 'packet length
  ip_id = $12     'datagram id
  ip_frag_offset = $14    'fragment offset
  ip_ttl = $16    'time to live
  ip_proto = $17  'protocol (ICMP=1, TCP=6, UDP=11)
  ip_hdr_cksum = $18      'header checksum 1a23
  ip_srcaddr = $1A        'IP address of source
  ip_destaddr = $1E       'IP addess of destination
  ip_data = $22   'IP data area
  '******************************************************************
  '*      TCP Header Layout
  '******************************************************************
  TCP_srcport = $22       'TCP source port
  TCP_destport = $24      'TCP destination port
  TCP_seqnum = $26        'sequence number
  TCP_acknum = $2A        'acknowledgement number
  TCP_hdrlen = $2E        '4-bit header len (upper 4 bits)
  TCP_hdrflags = $2F      'TCP flags
  TCP_window = $30        'window size
  TCP_cksum = $32 'TCP checksum
  TCP_urgentptr = $34     'urgent pointer
  TCP_data = $36 'option/data
  '******************************************************************
  '*      IP Protocol Types
  '******************************************************************
  PROT_ICMP = $01
  PROT_TCP = $06
  PROT_UDP = $11
  '******************************************************************
  '*      ICMP Header
  '******************************************************************
  ICMP_type = ip_data
  ICMP_code = ICMP_type+1
  ICMP_cksum = ICMP_code+1
  ICMP_id = ICMP_cksum+2
  ICMP_seqnum = ICMP_id+2
  ICMP_data = ICMP_seqnum+2
  '******************************************************************
  '*      UDP Header
  '******************************************************************
  UDP_srcport = ip_data
  UDP_destport = UDP_srcport+2
  UDP_len = UDP_destport+2
  UDP_cksum = UDP_len+2
  UDP_data = UDP_cksum+2
  '******************************************************************
  '*      DHCP Message
  '******************************************************************
  DHCP_op = UDP_data
  DHCP_htype = DHCP_op+1
  DHCP_hlen = DHCP_htype+1
  DHCP_hops = DHCP_hlen+1
  DHCP_xid = DHCP_hops+1
  DHCP_secs = DHCP_xid+4
  DHCP_flags = DHCP_secs+2
  DHCP_ciaddr = DHCP_flags+2
  DHCP_yiaddr = DHCP_ciaddr+4
  DHCP_siaddr = DHCP_yiaddr+4
  DHCP_giaddr = DHCP_siaddr+4
  DHCP_chaddr = DHCP_giaddr+4
  DHCP_sname = DHCP_chaddr+16
  DHCP_file = DHCP_sname+64
  DHCP_options = DHCP_file+128
  DHCP_message_end = DHCP_options+312