

defmodule Exownet.OWClient do
  defstruct [:address, :port, :flag, :socket, :persistence, :errors_map, :verbose]
  alias Exownet.OWPacket


@moduledoc """
A client for interacting with owserver. You probably want to use the `Exownet` application rather than use the client directly.

`Exownet.OWClient` provides a struct representing the connection information for an owserver.

## Types

  - `t()`: The client struct, which holds the state of the connection.
  - `error_tuple()`: Represents errors that can occur during the operation of the client.

## Example

Here's an example of how to use the client:

```elixir
client = Exownet.OWClient.new('localhost', 4304, [:persistence])
{:ok, client, dir_content} = Exownet.OWClient.dir(client, "/")
IO.inspect(dir_content)
```
This will connect to an OWServer running on localhost, port 4304, with connection persistence enabled, and then
fetch a directory listing of the root directory.
"""

  @type t :: %__MODULE__{
          address: charlist,
          port: integer,
          flag: integer,
          socket: :gen_tcp.socket() | nil,
        }

  @type owserver_error :: integer()
  @type socket_error :: atom()
  @type error_tuple :: {:error, String.t() | owserver_error() | socket_error()}
  @maxsize 65536

  @doc """
  Creates a new `OWClient` with the specified address, port, and flags.

  ## Parameters

  - `address`: A charlist or string representing the IP address or hostname of the OWServer. Defaults to `'localhost'`.
  - `port`: An integer representing the port number of the OWServer. Defaults to `4304`.
  - `flags`: A list of atoms representing flags for the client. Defaults to `[:persistence]`.

  ## Returns

  Returns a new `OWClient` struct with the specified address, port, and flags. The socket field of the struct is initially set to `nil`.

  """
  @spec new(charlist | String.t(), integer, OWPacket.flag_list()) :: t()
  def new(address \\ 'localhost', port \\ 4304, flags \\ [:persistence]) do
    %__MODULE__{
      address: to_charlist(address),
      port: port,
      flag: OWPacket.update_flag(flags, 0),
      socket: nil
    }
  end

  @doc """
  Sends a 'No Operation' (NOP) packet to the OWServer, acting as a 'ping'.
  Can be used to keeps a persistent connection alive.

  ## Params
  - `client`: The `OWClient` struct
  - `flags`: Optional. A list of flags to send for this message only.

  ## Returns
  Returns an `{:ok, t()}` tuple on success, where `t()` is the updated `OWClient` struct. If the server
  keeps the connection open, it will set the persistence flag in the client struct.

  In case of failure, it returns an error tuple `{:error, reason}`

  """
  @spec ping(t(), OWPacket.flag_list()) :: {:ok, t()} | error_tuple
  def ping(client, flags \\ []) do
    flags = OWPacket.update_flag(flags, client.flag)
    req_packet = OWPacket.create_packet(:NOP, <<>>, flags)

    with {:ok, client} <- maybe_reconnect(client),
         :ok <- send_packet(client.socket, req_packet),
         {:ok, header, _payload} = receive_message(client.socket) do
      {:ok, update_persistence(client, header)}
    end
  end

  @doc """
  Sends a DIRALLSLASH packet to the OWServer. Returns a list of directories and/or endpoints located at the specified path.
  Directories end with a `/`.

  ## Params
  - `client`: The `OWClient` struct
  - `path`: A string representing a directory to list the contents of. Defaults to "/"
  - `flags`: Optional. A list of flags to send for this message only.

  ## Returns
  Returns a tuple of `{:ok, t(), list(String.t())}` where the list of strings are folders and/or endpoints at the path.

  On failure, returns `{:error, reason}`.
  """
  @spec dir(t(), String.t(), OWPacket.flag_list()) :: {:ok, t(), list(String.t())} | error_tuple
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

  @doc """
  Reads data from the specified path on the OWServer.

  ## Params
  - `client`: The `OWClient` struct
  - `path`: A string representing the path you want to read the contents of.
  - `flags`: Optional. A list of flags to send for this message only.

  ## Returns
  Returns an tuple of `{:ok, t(), <<>>}` where the bitstring contains the read value
  """
  @spec read(t(), String.t(), OWPacket.flag_list()) :: {:ok, t(), <<>>} | error_tuple
  def read(client, path, opt_flags \\ []) do
    flags = OWPacket.update_flag(opt_flags, client.flag)
    req_packet = OWPacket.create_packet(:READ, path <> <<0>>, flags, @maxsize, 0)

    with {:ok, client} <- maybe_reconnect(client),
         :ok <- send_packet(client.socket, req_packet),
         {:ok, header, payload} <- receive_non_empty_message(client.socket) do
      {:ok, update_persistence(client, header), payload}
    end
  end

@doc """
Writes data to the specified path.

## Parameters

- `client`: The `OWClient` struct which contains connection information.
- `path`: The path on the server where the value will be written.
- `value`: The value to write. It can be a binary, string, boolean, :on, or :off. For booleans, :on, and :off,
  it will be converted to <<"1">> or <<"0">> respectively.
- `opt_flags`: Optional. A list of atoms representing flags for the client. These flags are updated in the client's
  current flag state before the write request.

## Returns

Returns an `{:ok, t()}` tuple on success, where `t()` is the updated `OWClient` struct.

In case of failure, it returns an error tuple `{:error, reason}` where `reason` is a string, an integer or an atom
indicating the reason for the failure.

"""
  @spec write(t(), String.t(), binary() | String.t() | boolean | :on | :off, OWPacket.flag_list()) :: {:ok, t()} | error_tuple
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

  @spec update_persistence(t(), OWPacket.header()) :: t()
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

  @spec receive_message(:gen_tcp.socket()) :: {:ok, OWPacket.header(), <<>>} | error_tuple
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

  @spec receive_payload(:gen_tcp.socket(), OWPacket.header()) :: {:ok, OWPacket.header(), <<>>} | error_tuple
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

  @spec receive_non_empty_message(:gen_tcp.socket()) :: {:ok, OWPacket.header(), <<>>} | error_tuple
  defp receive_non_empty_message(socket) do
    # Keeps calling receive_message until it receives a message with a payload or an error is returned
    case receive_message(socket) do
      {:ok, _header, <<>>} -> receive_non_empty_message(socket)
      {:ok, header, data} -> {:ok, header, data}
      {:error, reason} -> {:error, reason}
    end
  end
end
