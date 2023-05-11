
defmodule Exownet.OWClient do
  defstruct [:address, :port, :flag, :socket, :persistence, :errors_map, :verbose]
  alias Exownet.OWPacket

  @type t :: %__MODULE__{
          address: charlist,
          port: integer,
          flag: integer,
          socket: :gen_tcp.socket() | nil,
        }

  @type error_tuple :: {:error, any()}

  @maxsize 65536

  @spec new(charlist | String.t(), integer, list(atom)) :: t()
  def new(address \\ 'localhost', port \\ 4304, flags \\ [:persistence]) do
    %__MODULE__{
      address: to_charlist(address),
      port: port,
      flag: OWPacket.update_flag(flags, 0),
      socket: nil
    }
  end

  @spec ping(t(), list(atom)) :: {:ok, t()} | error_tuple
  def ping(client, flags \\ []) do
    flags = OWPacket.update_flag(flags, client.flag)
    req_packet = OWPacket.create_packet(:NOP, <<>>, flags)

    with {:ok, client} <- maybe_reconnect(client),
         :ok <- send_packet(client.socket, req_packet),
         {:ok, header, _payload} = receive_message(client.socket) do
      {:ok, update_persistence(client, header)}
    end
  end

  @spec dir(t(), String.t(), list(atom)) :: {:ok, t(), list(String.t())} | error_tuple
  def dir(client, path \\ "/", opt_flags \\ []) do
    flags = OWPacket.update_flag(opt_flags, client.flag)
    req_packet = OWPacket.create_packet(:DIRALLSLASH, path <> <<0>>, flags)

    with {:ok, client} <- maybe_reconnect(client),
         :ok <- send_packet(client.socket, req_packet),
         {:ok, header, payload} <- receive_non_empty_message(client.socket) do

      values = # "/28.32D7E0080000,/42.C2D154000000\0"
        payload
        |> String.slice(0..-2)
        |> String.split(",")

      {:ok, update_persistence(client, header), values}
    end
  end

  @spec read(t(), String.t(), list(atom)) :: {:ok, t(), String.t()} | error_tuple
  def read(client, path, opt_flags \\ []) do
    flags = OWPacket.update_flag(opt_flags, client.flag)
    req_packet = OWPacket.create_packet(:READ, path <> <<0>>, flags, @maxsize, 0)

    with {:ok, client} <- maybe_reconnect(client),
         :ok <- send_packet(client.socket, req_packet),
         {:ok, header, payload} <- receive_non_empty_message(client.socket) do
      {:ok, update_persistence(client, header), payload}
    end
  end

  @spec write(t(), String.t(), binary() | String.t() | boolean | :on | :off, list(atom)) :: {:ok, t(), binary()} | error_tuple
  def write(client, path, value, opt_flags \\ [])
  def write(client, path, true, opt_flags), do: write(client, path, <<?1>>, opt_flags)
  def write(client, path, :on, opt_flags), do: write(client, path, <<?1>>, opt_flags)
  def write(client, path, false, opt_flags), do: write(client, path, <<?0>>, opt_flags)
  def write(client, path, :off, opt_flags), do: write(client, path, <<?0>>, opt_flags)

  def write(client, path, value, opt_flags) when is_binary(value) do
    flags = OWPacket.update_flag(opt_flags, client.flag)
    payload = path <> <<0>> <> value
    req_packet = OWPacket.create_packet(:WRITE, payload, flags, byte_size(value), 0)

    with {:ok, client} <- maybe_reconnect(client),
         :ok <- send_packet(client.socket, req_packet),
         {:ok, header, payload} <- receive_message(client.socket) do
      {:ok, update_persistence(client, header), payload}
    end
  end

  # owserver was originally developed to only allow one command per connection. There was no way of
  # keeping a socket open to send multiple commands. A persistent socket was later added as a feature,
  # but it is not guaranteed. The server might still close the connection on us; if the server is keeping
  # the connection open, it will set the persistence flag
  @spec maybe_reconnect(t()) :: {:ok, t()} | error_tuple
  defp maybe_reconnect(client) when client.socket == nil do
    # persistence not granted, reconnect to server
    with {:ok, socket} <- connect(client.address, client.port) do
      {:ok, %{client | socket: socket}}
    end
  end

  defp maybe_reconnect(client) do
    # persistence granted, return client untouched
    {:ok, client}
  end

  @spec update_persistence(t(), binary()) :: t()
  defp update_persistence(client, header) do
    if OWPacket.persistence_granted?(header) do
      # Keep socket around for next iteration
      client
    else
      # Close and toss socket, owfs server is done with it.
      close_socket(client.socket)
      %{client | socket: nil}
    end
  end

  @spec connect(charlist(), integer()) :: {:ok, :gen_tcp.socket()} | error_tuple
  defp connect(address, port), do: :gen_tcp.connect(address, port, [:binary, active: false])

  @spec send_packet(:gen_tcp.socket(), binary()) :: :ok | error_tuple
  defp send_packet(socket, packet), do: :gen_tcp.send(socket, packet)

  @spec receive_packet(:gen_tcp.socket(), integer()) :: {:ok, binary()} | error_tuple
  defp receive_packet(socket, num_bytes), do: :gen_tcp.recv(socket, num_bytes)

  @spec close_socket(:gen_tcp.socket()) :: :ok
  defp close_socket(socket), do: :gen_tcp.close(socket)



  @spec receive_message(:gen_tcp.socket()) :: {:ok, binary(), binary()} | error_tuple
  defp receive_message(socket) do
    with {:ok, header} <- receive_packet(socket, 24) do
      ret_code = OWPacket.return_code(header)
      if ret_code < 0 do
        {:error, -ret_code}
      else
        receive_payload(socket, header)
      end

    end
  end

  @spec receive_payload(:gen_tcp.socket(), binary()) :: {:ok, binary(), binary()} | error_tuple
  defp receive_payload(socket, header) do
    payload_size = OWPacket.payload_size(header)

    if payload_size > 0 do
      with {:ok, payload} <- receive_packet(socket, payload_size) do
        {:ok, header, payload}
      else
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, header, <<>>}
    end
  end

  @spec receive_non_empty_message(:gen_tcp.socket()) :: {:ok, binary(), binary()} | error_tuple
  defp receive_non_empty_message(socket) do
    # Keeps calling receive_message until it receives a message with a payload or an error is returned
    case receive_message(socket) do
      {:ok, _header, <<>>} -> receive_non_empty_message(socket)
      {:ok, header, data} -> {:ok, header, data}
      {:error, reason} -> {:error, reason}
    end
  end
end
