
defmodule Ownet.Packet do
  import Bitwise

  @moduledoc false

  # The `Ownet.Packet` module provides functionality for creating and manipulating owserver (One-Wire File System) packets.
  #
  # This module allows you to create packets with `create_packet/5`, create packet flags with `calculate_flag/2`, and check for granted persistence with `persistence_granted?/1`.
  #
  # The module also provides several decoding utilities:
  # - `decode_outgoing_packet/1`
  # - `decode_incoming_packet/1`
  #
  # The module defines the following types:
  # - `message_type`: Represents different types of owserver messages.
  # - `flag_value`: Represents different flags that can be set on an OWFS message.
  # - `flag_list`: Represents a list of `flag_value`s.
  # - `header`: Represents the binary header of an owserver packet.
  # - `packet`: Represents an entire OWFS packet, including the header and payload.
  # - `decoded_outgoing_packet_header`: Represents the structure of a decoded outgoing packet header as a map.
  # - `decoded_incoming_packet_header`: Represents the structure of a decoded incoming packet header as a map.
  #
  # The module also defines constants for message types and flags. These constants include various options and scales (for temperature, pressure, and address displays) that are used in OWFS messages.

  @type message_type :: :ERROR | :NOP | :READ | :WRITE | :DIR | :SIZE | :PRESENT | :DIRALL | :GET | :DIRALLSLASH | :GETSLASH
  @type flag_value :: :uncached | :safemode | :alias | :persistence | :bus_ret | :ownet | :c | :f | :k | :r |
                      :mbar | :atm | :mmhg | :inhg | :psi | :pa | :fdi | :fi | :fdidc | :fdic | :fidc | :fic
  @type flag_list :: list(flag_value())
  @type header :: <<_:: 192>> #header consists of 6 * 32-bit integers
  @type packet :: <<_:: 192, _::_*1>> #header + payload

  @type decoded_outgoing_packet_header :: %{
    :version => integer(),
    :payloadsize => integer(),
    :type => integer(),
    :flag => integer(),
    :size => integer(),
    :offset => integer(),
    :payload => binary()
  }

  @type decoded_incoming_packet_header :: %{
    :flag => integer(),
    :offset => integer(),
    :payloadsize => integer(),
    :ret => integer(),
    :size => integer(),
    :version => integer(),
    :payload => binary()
  }

  @version 0
  @expected_size 0
  @offset 0

  @message_types %{
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



  @doc """
  Creates an outgoing OWFS packet with the given parameters.

  ## Params

  - `type`: A `message_type` that represents the type of the message. This should be one of the values defined in `@message_types`.
  - `payload`: A `bitstring` that represents the payload of the packet.
  - `flags`: An `integer` that represents the flags to be set for the packet. Flags should be derived from `@flags`.
  - `expected_size` (optional): An `integer` that represents the expected size of the packet. Defaults to `@expected_size`.
  - `offset` (optional): An `integer` that represents the offset of the packet. Defaults to `@offset`.

  ## Returns

  - A `packet` which is a binary that represents the OWFS packet. This binary includes the packet header and the payload.
  """
  @spec create_packet(message_type(), bitstring(), integer(), integer(), integer()) :: packet()
  def create_packet(
        type,
        payload,
        flags,
        expected_size \\ @expected_size,
        offset \\ @offset
      ) do
    header = <<@version::32-big, byte_size(payload)::32-big, @message_types[type]::32-big,
              flags::32-big, expected_size::32-big, offset::32-big>>

    header <> payload
  end

  @spec calculate_flag(flag_list(), integer()) :: integer()
  def calculate_flag(flags, current_value \\ 0) do
    # Takes a list of flags and the current flag value, and computes a new flag value.
    # This will allow you to set invalid flag combinations (e.g. setting multiple temperature scales)
    Enum.reduce(flags, current_value, fn flag, acc -> @flags[flag] ||| acc end)
  end


  @spec persistence_granted?(header()) :: boolean()
  def persistence_granted?(header) do
    # Returns true if the provided header's flag value has set the "persistence" value to true. This indicates the owserver will
    # keep the socket open to receive another command.
    flag = flags(header)
    (flag &&& @flags[:persistence]) == @flags[:persistence]
  end

  @spec payload_size(header()) :: integer()
  def payload_size(header) do
    # Returns the size of the payload that follows the header.
    <<_version::32, payloadsize::32-integer-signed-big, _rest::binary>> = header
    payloadsize
  end

  @spec return_code(header()) :: integer()
  def return_code(header) do
    # Returns the return code. The return code is a header value that indicates either success (0) or an error code.
    # Error codes are always negative.
    <<_version_payload::64, ret_code::32-integer-signed-big, _rest::binary>> = header
    ret_code
  end

  @spec flags(header()) :: integer()
  def flags(header) do
    # Returns the flag value of the supplied header.
    <<_version_payload_type::96, header::32-integer-signed-big, _rest::binary>> = header
    header
  end

  @spec decode_outgoing_packet(header()) :: decoded_outgoing_packet_header()
  def decode_outgoing_packet(data) do
    # Returns a map representation of an outgoing header.
    <<version::32-integer-signed-big, payloadsize::32-integer-signed-big,
      type::32-integer-signed-big, flag::32-integer-signed-big, size::32-integer-signed-big,
      offset::32-integer-signed-big, payload::binary>> = data

    %{
      version: version,
      payloadsize: payloadsize,
      type: type,
      flag: flag,
      size: size,
      offset: offset,
      payload: payload
    }
  end

  @spec decode_incoming_packet(header) :: decoded_incoming_packet_header()
  def decode_incoming_packet(data) do
    # Returns a map representation of an incoming header.
    <<version::32-integer-signed-big, payloadsize::32-integer-signed-big,
      ret::32-integer-signed-big, flag::32-integer-signed-big, size::32-integer-signed-big,
      offset::32-integer-signed-big, payload::binary>> = data

    %{
      version: version,
      payloadsize: payloadsize,
      ret: ret,
      flag: flag,
      size: size,
      offset: offset,
      payload: payload
    }
  end
end
