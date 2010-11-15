CON
  _CLKMODE = XTAL1 + PLL16X
  _XINFREQ = 5_000_000

DAT
  mac_addr      byte    $02, $00, $00, $00, $00, $05    ' device mac address, must be unique

                long
  ip_addr       byte    192, 168, 1, 200                ' device's ip address
  ip_subnet     byte    255, 255, 255, 0                ' network subnet
  ip_gateway    byte    192, 168, 1, 1                  ' network gateway (router)
  ip_dns        byte    192, 168, 1, 1                  ' network dns

CON
  ' buffer sizes, must be a power of 2
  rxlen  = 1024
  txlen  = 1024
  cmdlen = 512

VAR
  byte tcp_rx[rxlen]        ' buffers for socket
  byte tcp_tx[txlen]

  byte cmd_buf[cmdlen]

OBJ
'  command : "SpinCommand"
  interpreter : "GCodeInterpreter"
  pins    : "Pins"
  socket  : "api_telnet_serial"
  serial  : "SerialMirror"

PUB main | cmd, status, i

  interpreter.init

  serial.start(31, 30, 0, 115200)

'  processStream

  'Init the TCP/IP driver
  socket.start(Pins#ETH_CS, Pins#ETH_SCK, Pins#ETH_SI, Pins#ETH_SO, Pins#ETH_INT, -1, @mac_addr, @ip_addr)

  \socket.listen(4004, @tcp_rx, rxlen, @tcp_tx, txlen)

  repeat
    if \socket.isConnected      'Process the stream when a client connects
      processStream

PRI processStream | i, info
  repeat
    ifnot \socket.isConnected
      return
    else
      i := 0
      repeat while cmd_buf[i-1] <> $0A and i < 200
        cmd_buf[i] := socket.rx
        serial.tx(cmd_buf[i])
        i++
      cmd_buf[i-1] := 0
      info := interpreter.processCommand(@cmd_buf)
      socket.str(info)
      serial.str(info)
      socket.txflush

