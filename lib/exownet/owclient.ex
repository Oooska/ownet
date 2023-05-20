defmodule Exownet.OWClient do
  alias Exownet.OWPacket
  alias Exownet.Socket

  @ownet_error :ownet_error
  @maxsize 65536
  @type socket_error :: {:error, :inet.posix()}
  @type ownet_error :: {:ownet_error, integer(), boolean()}
  @type error_tuple :: socket_error | ownet_error

  @spec ping(:gen_tcp.socket(), OWPacket.flag_list()) :: {:ok, boolean()} | error_tuple()
  def ping(socket, flags \\ []) do
    flags = OWPacket.calculate_flag(flags, 0)
    req_packet = OWPacket.create_packet(:NOP, <<>>, flags)

    case send_and_receive_response(socket, req_packet) do
      {:ok, _header, _payload, persistence} -> {:ok, persistence}
      error -> error
    end
  end

  @spec present(:gen_tcp.socket(), String.t, OWPacket.flag_list()) ::{:ok, boolean(), boolean()} | error_tuple()
  def present(socket, path, flags \\ []) do
    flags = OWPacket.calculate_flag(flags, 0)
    req_packet = OWPacket.create_packet(:PRESENT, path <> <<0>>, flags)

    case send_and_receive_response(socket, req_packet) do
      {:ok, _header, _payload, persistence} -> {:ok, true, persistence}
      {:ownet_error, ret_code, persistence} when is_integer(ret_code) -> {:ok, false, persistence}
      error -> error
    end
  end

  @spec dir(:gen_tcp.socket(), String.t(), OWPacket.flag_list()) :: {:ok, list(String.t()), boolean()} |  error_tuple()
  def dir(socket, path \\ "/", flags \\ []) do
    flags = OWPacket.calculate_flag(flags, 0)
    req_packet = OWPacket.create_packet(:DIRALLSLASH, path <> <<0>>, flags)

    case send_and_receive_response_with_payload(socket, req_packet) do
      {:ok, _header, payload, persistence} ->
        values =
          payload # "/28.32D7E0080000,/42.C2D154000000\0"
          |> String.slice(0..-2)
          |> String.split(",")
        {:ok, values, persistence}

      error -> error
    end
  end

  @spec read(:gen_tcp.socket(), String.t(), OWPacket.flag_list()) :: {:ok, binary(), boolean()} |  error_tuple()
  def read(socket, path, flags \\ []) do
    flags = OWPacket.calculate_flag(flags, 0)
    req_packet = OWPacket.create_packet(:READ, path <> <<0>>, flags, @maxsize, 0)

    case send_and_receive_response_with_payload(socket, req_packet) do
      {:ok, _header, payload, persistence} -> {:ok, payload, persistence}
      error -> error
    end
  end

  @spec write(:gen_tcp.socket(), String.t(), binary() | String.t() | boolean() | :on | :off, OWPacket.flag_list()) :: {:ok, boolean()} |  error_tuple()
  def write(socket, path, value, flags \\ [])
  def write(socket, path, true, flags), do: write(socket, path, <<?1>>, flags)
  def write(socket, path, :on, flags), do: write(socket, path, <<?1>>, flags)
  def write(socket, path, false, flags), do: write(socket, path, <<?0>>, flags)
  def write(socket, path, :off, flags), do: write(socket, path, <<?0>>, flags)
  def write(socket, path, value, flags) do
    flags = OWPacket.calculate_flag(flags, 0)
    payload = path <> <<0>> <> value
    req_packet = OWPacket.create_packet(:WRITE, payload, flags, byte_size(value), 0)
    case send_and_receive_response(socket, req_packet) do
      {:ok, _header, _payload, persistence} -> {:ok, persistence}
      error -> error
    end
  end

  @spec send_and_receive_response(:gen_tcp.socket(), OWPacket.packet()) :: {:ok, OWPacket.header(), binary(), boolean()} | error_tuple
  defp send_and_receive_response(socket, packet) do
    with :ok <- Socket.send(socket, packet),
         {:ok, header, payload, persistence} <- receive_next_message(socket) do
      {:ok, header, payload, persistence}
    end
  end

  @spec send_and_receive_response_with_payload(:gen_tcp.socket(), OWPacket.packet()) :: {:ok, OWPacket.header(), binary(), boolean()} | error_tuple
  defp send_and_receive_response_with_payload(socket, packet) do
    with :ok <- Socket.send(socket, packet),
         {:ok, header, payload, persistence} <- receive_next_message_with_payload(socket) do
      {:ok, header, payload, persistence}
    end
  end

  @spec receive_next_message(:gen_tcp.socket()) :: {:ok, OWPacket.header(), binary(), boolean()} | error_tuple
  defp receive_next_message(socket) do
    with {:ok, header} <- receive_header(socket),
         {:ok, header, payload} <- receive_payload(socket, header) do

      ret_code = OWPacket.return_code(header)
      if ret_code >= 0 do
        IO.inspect({OWPacket.decode_incoming_packet_header(header), payload}, label: "ret code >= 0", binaries: :as_strings)
        {:ok, header, payload, OWPacket.persistence_granted?(header)}
      else
        IO.inspect({OWPacket.decode_incoming_packet_header(header), payload}, label: "ret code != 0", binaries: :as_strings)
        {@ownet_error, -ret_code, OWPacket.persistence_granted?(header)}
      end
    end
  end

  @spec receive_next_message_with_payload(:gen_tcp.socket()) :: {:ok, OWPacket.header(), binary(), boolean()} | error_tuple()
  defp receive_next_message_with_payload(socket) do
    case receive_next_message(socket) do
      {:ok, _header, <<>>, _persistence_granted} -> receive_next_message_with_payload(socket)
      {:ok, header, payload, persistence_granted} -> {:ok, header, payload, persistence_granted}
      {@ownet_error, ret_code, persistence_granted} -> {@ownet_error, ret_code, persistence_granted}
      {:error, reason} -> {:error, reason}
    end
  end


  @spec receive_header(:gen_tcp.socket()) :: {:ok, OWPacket.header()} | socket_error()
  defp receive_header(socket) do
    Socket.recv(socket, 24)
  end

  @spec receive_payload(:gen_tcp.socket(), OWPacket.header()) :: {:ok, OWPacket.header(), binary()} | socket_error()
  defp receive_payload(socket, header) do
    payload_size = OWPacket.payload_size(header)

    if payload_size > 0 do
      case Socket.recv(socket, payload_size) do
        {:ok, payload} -> {:ok, header, payload}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, header, <<>>}
    end
  end
end
