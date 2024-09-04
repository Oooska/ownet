defmodule Ownet.Socket do
  require Logger
  alias Ownet.Packet

  @maxsize 65536
  @type socket_error :: {:error, :inet.posix()}
  @type ownet_error :: {:ownet_error, integer()}
  @type error_tuple :: socket_error | ownet_error

  @spec ping(:gen_tcp.socket(), Packet.flag_list()) :: :ok | error_tuple()
  def ping(socket, flags \\ []) do
    flags = Packet.calculate_flag(flags, 0)
    req_packet = Packet.create_packet(:NOP, <<>>, flags)

    case send_and_receive_response(socket, req_packet) do
      {:ok, _header, _payload} -> :ok
      error -> error
    end
  end

  @spec present(:gen_tcp.socket(), String.t(), Packet.flag_list()) ::
          {:ok, boolean()} | error_tuple()
  def present(socket, path, flags \\ []) do
    flags = Packet.calculate_flag(flags, 0)
    req_packet = Packet.create_packet(:PRESENT, path <> <<0>>, flags)

    case send_and_receive_response(socket, req_packet) do
      {:ok, _header, _payload} -> {:ok, true}
      {:ownet_error, ret_code} when is_integer(ret_code) -> {:ok, false}
      error -> error
    end
  end

  @spec dir(:gen_tcp.socket(), String.t(), Packet.flag_list()) ::
          {:ok, list(String.t())} | error_tuple()
  def dir(socket, path \\ "/", flags \\ []) do
    flags = Packet.calculate_flag(flags, 0)
    req_packet = Packet.create_packet(:DIRALLSLASH, path <> <<0>>, flags)

    case send_and_receive_response_with_payload(socket, req_packet) do
      {:ok, _header, payload} ->
        # "/28.32D7E0080000,/42.C2D154000000\0"
        values =
          payload
          |> String.slice(0..-2//1)
          |> String.split(",")

        {:ok, values}

      error ->
        error
    end
  end

  @spec read(:gen_tcp.socket(), String.t(), Packet.flag_list()) ::
          {:ok, binary()} | error_tuple()
  def read(socket, path, flags \\ []) do
    flags = Packet.calculate_flag(flags, 0)
    req_packet = Packet.create_packet(:READ, path <> <<0>>, flags, @maxsize, 0)

    case send_and_receive_response_with_payload(socket, req_packet) do
      {:ok, _header, payload} -> {:ok, payload}
      error -> error
    end
  end

  @spec write(
          :gen_tcp.socket(),
          String.t(),
          binary() | String.t() | boolean() | :on | :off,
          Packet.flag_list()
        ) :: :ok | error_tuple()
  def write(socket, path, value, flags \\ [])
  def write(socket, path, true, flags), do: write(socket, path, "1", flags)
  def write(socket, path, :on, flags), do: write(socket, path, "1", flags)
  def write(socket, path, false, flags), do: write(socket, path, "0", flags)
  def write(socket, path, :off, flags), do: write(socket, path, "0", flags)

  def write(socket, path, value, flags) do
    flags = Packet.calculate_flag(flags, 0)
    payload = path <> <<0>> <> value
    req_packet = Packet.create_packet(:WRITE, payload, flags, byte_size(value), 0)

    case send_and_receive_response(socket, req_packet) do
      {:ok, _header, _payload} -> :ok
      error -> error
    end
  end

  @spec send_and_receive_response(:gen_tcp.socket(), Packet.packet()) ::
          {:ok, Packet.header(), binary()} | error_tuple
  defp send_and_receive_response(socket, packet) do
    with :ok <- send_message(socket, packet),
         {:ok, header, payload} <- receive_next_message(socket) do
      {:ok, header, payload}
    end
  end

  @spec send_and_receive_response_with_payload(:gen_tcp.socket(), Packet.packet()) ::
          {:ok, Packet.header(), binary()} | error_tuple
  defp send_and_receive_response_with_payload(socket, packet) do
    with :ok <- send_message(socket, packet),
         {:ok, header, payload} <- receive_next_message_with_payload(socket) do
      {:ok, header, payload}
    end
  end

  @spec send_message(:gen_tcp.socket(), binary()) :: :ok | socket_error
  defp send_message(socket, packet) do
    Logger.debug(
      "Sending message: #{inspect(Packet.decode_outgoing_packet(packet), binaries: :as_strings)}"
    )

    :gen_tcp.send(socket, packet)
  end

  @spec receive_next_message(:gen_tcp.socket()) ::
          {:ok, Packet.header(), binary()} | error_tuple
  defp receive_next_message(socket) do
    with {:ok, header} <- receive_header(socket),
         {:ok, header, payload} <- receive_payload(socket, header) do
      Logger.debug(
        "Received message: #{inspect(Packet.decode_incoming_packet(header <> payload), binaries: :as_strings)}"
      )

      ret_code = Packet.return_code(header)

      if ret_code >= 0 do
        # IO.inspect({Packet.decode_incoming_packet(header), payload}, label: "ret code >= 0", binaries: :as_strings)
        {:ok, header, payload}
      else
        # IO.inspect({Packet.decode_incoming_packet(header), payload}, label: "ret code != 0", binaries: :as_strings)
        {:ownet_error, -ret_code}
      end
    end
  end

  @spec receive_next_message_with_payload(:gen_tcp.socket()) ::
          {:ok, Packet.header(), binary()} | error_tuple()
  defp receive_next_message_with_payload(socket) do
    case receive_next_message(socket) do
      {:ok, _header, <<>>} ->
        receive_next_message_with_payload(socket)

      {:ok, header, payload} ->
        {:ok, header, payload}

      {:ownet_error, ret_code} ->
        {:ownet_error, ret_code}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec receive_header(:gen_tcp.socket()) :: {:ok, Packet.header()} | socket_error()
  defp receive_header(socket) do
    :gen_tcp.recv(socket, 24)
  end

  @spec receive_payload(:gen_tcp.socket(), Packet.header()) ::
          {:ok, Packet.header(), binary()} | socket_error()
  defp receive_payload(socket, header) do
    payload_size = Packet.payload_size(header)

    if payload_size > 0 do
      case :gen_tcp.recv(socket, payload_size) do
        {:ok, payload} -> {:ok, header, payload}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, header, <<>>}
    end
  end
end
