
defmodule Exownet.OWPacket do
  import Bitwise

  @message_type %{
    ERROR: 0,
    NOP: 1,
    READ: 2,
    WRITE: 3,
    DIR: 4,
    SIZE: 5,
    PRESENT: 6,
    DIRALL: 7,
    GET: 8,
    DIRALLSLASH: 9,
    GETSLASH: 10
  }

  @version 0
  @expected_size 0
  @offset 0

  @flags %{
    # owfs options
    uncached: 0x00000020,    # skips owfs cache
    safemode: 0x00000010,    # 'Restricts operations to reads and cached'
    alias: 0x00000008,       # 'Use aliases for known slaves (human readable names)
    persistence: 0x00000004, # keeps socket alive between calls
    bus_ret: 0x00000002,     # 'Include special directories (settings, statistics, uncached,...)'
    ownet: 0x00000100,       # from owfs

    # temperature scales
    c: 0x00000000,    # default
    f: 0x00010000,
    k: 0x00020000,
    r: 0x00030000,

    # pressure scales
    mbar: 0x00000000,  # default
    atm: 0x00040000,
    mmhg: 0x00080000,
    inhg: 0x000C0000,
    psi: 0x00100000,
    pa: 0x00140000,

    # Address displays
    fdi: 0x00000000,   #f.i (/42.C2D154000000/) - default
    fi: 0x01000000,    #fi (/42C2D154000000/)
    fdidc: 0x02000000, #f.i.c (/42.C2D154000000.09/)
    fdic: 0x03000000,  #f.ic (/42.C2D15400000009/)
    fidc: 0x04000000,  #fi.c (/42C2D154000000.09/)
    fic: 0x05000000    #fic (/42C2D15400000009/)
  }

  def create_packet(
        type,
        payload,
        flags,
        expected_size \\ @expected_size,
        offset \\ @offset
      ) do
    header = <<@version::32-big, byte_size(payload)::32-big, @message_type[type]::32-big,
              flags::32-big, expected_size::32-big, offset::32-big>>

    header <> payload
  end

  def update_flag(flags, current_value) do
      Enum.reduce(flags, current_value, fn flag, acc -> @flags[flag] ||| acc end)
  end

  # https://owfs.org/index_php_page_tcp-messages.html

  def persistence_granted?(header) do
    flag = flags(header)
    (flag &&& @flags[:persistence]) == @flags[:persistence]
  end

  def payload_size(header) do
    <<_version::32, payloadsize::32-integer-signed-big, _rest::binary>> = header
    payloadsize
  end

  def return_code(header) do
    <<_version_payload::64, ret_code::32-integer-signed-big, _rest::binary>> = header
    ret_code
  end

  def flags(header) do
    <<_version_payload_type::96, header::32-integer-signed-big, _rest::binary>> = header
    header
  end

  def decode_outgoing_packet_header(data) do
    <<version::32-integer-signed-big, payloadsize::32-integer-signed-big,
      type::32-integer-signed-big, flag::32-integer-signed-big, size::32-integer-signed-big,
      offset::32-integer-signed-big>> = data

    %{
      version: version,
      payloadsize: payloadsize,
      type: type,
      flag: flag,
      size: size,
      offset: offset
    }
  end

  def decode_incoming_packet_header(data) do
    <<version::32-integer-signed-big, payloadsize::32-integer-signed-big,
      ret::32-integer-signed-big, flag::32-integer-signed-big, size::32-integer-signed-big,
      offset::32-integer-signed-big>> = data

    %{
      version: version,
      payloadsize: payloadsize,
      ret: ret,
      flag: flag,
      size: size,
      offset: offset
    }
  end
end
