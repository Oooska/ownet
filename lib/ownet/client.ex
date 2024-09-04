defmodule Ownet.Client do
  defstruct [:address, :port, :flags, :socket]
  alias Ownet.{Packet, Socket}

  @type t :: %__MODULE__{
          address: charlist(),
          port: integer(),
          flags: Packet.flag_list(),
          socket: :gen_tcp.socket() | nil
        }

  # Ownet.Client is a struct that holds the address, port, flags, and socket of the client.
  # The functions return a tuple with the updated client socket and the result of the operation.

  @spec new(charlist() | binary(), integer(), Packet.flag_list()) :: t()
  def new(address, port \\ 4304, flags \\ [:persistence])

  def new(address, port, flags) when is_binary(address) do
    new(to_charlist(address), port, flags)
  end

  def new(address, port, flags) do
    %__MODULE__{
      address: address,
      port: port,
      flags: flags,
      socket: nil
    }
  end

  @spec ping(t(), Packet.flag_list()) ::
          {t(), :ok} | {t(), {:error, :inet.posix()}} | {t(), {:error, String.t()}}
  def ping(client, flags \\ []) do
    case call_and_reconnect_if_closed(client, fn client ->
           Socket.ping(client.socket, flags ++ client.flags)
         end) do
      {client, :ok} -> {client, :ok}
      {client, {:ownet_error, reason}} -> {client, {:error, lookup_error(reason)}}
      {client, {:error, reason}} -> {client, {:error, reason}}
    end
  end

  @spec present(t(), String.t(), Packet.flag_list()) ::
          {t(), {:ok, boolean()}} | {t(), {:error, :inet.posix()}} | {t(), {:error, String.t()}}
  def present(client, path, flags \\ []) do
    case call_and_reconnect_if_closed(client, fn client ->
           Socket.present(client.socket, path, flags ++ client.flags)
         end) do
      {client, {:ok, present}} -> {client, {:ok, present}}
      {client, {:ownet_error, reason}} -> {client, {:error, lookup_error(reason)}}
      {client, {:error, reason}} -> {client, {:error, reason}}
    end
  end

  @spec dir(t(), String.t(), Packet.flag_list()) ::
          {t(), {:ok, list(String.t())}}
          | {t(), {:error, :inet.posix()}}
          | {t(), {:error, String.t()}}
  def dir(client, path, flags \\ []) do
    case call_and_reconnect_if_closed(client, fn client ->
           Socket.dir(client.socket, path, flags ++ client.flags)
         end) do
      {client, {:ok, paths}} -> {client, {:ok, paths}}
      {client, {:ownet_error, reason}} -> {client, {:error, lookup_error(reason)}}
      {client, {:error, reason}} -> {client, {:error, reason}}
    end
  end

  @spec read(t(), String.t(), Packet.flag_list()) ::
          {t(), {:ok, binary()}} | {t(), {:error, :inet.posix()}} | {t(), {:error, String.t()}}
  def read(client, path, flags \\ []) do
    case call_and_reconnect_if_closed(client, fn client ->
           Socket.read(client.socket, path, flags ++ client.flags)
         end) do
      {client, {:ok, value}} -> {client, {:ok, value}}
      {client, {:ownet_error, reason}} -> {client, {:error, lookup_error(reason)}}
      {client, {:error, reason}} -> {client, {:error, reason}}
    end
  end

  @spec write(t(), String.t(), binary(), Packet.flag_list()) ::
          {t(), :ok} | {t(), {:error, :inet.posix()}} | {t(), {:error, String.t()}}
  def write(client, path, value, flags \\ []) do
    case call_and_reconnect_if_closed(client, fn client ->
           Socket.write(client.socket, path, value, flags ++ client.flags)
         end) do
      {client, :ok} -> {client, :ok}
      {client, {:ownet_error, reason}} -> {client, {:error, lookup_error(reason)}}
      {client, {:error, reason}} -> {client, {:error, reason}}
    end
  end

  defp reconnect(client) do
    case :gen_tcp.connect(client.address, client.port, [:binary, active: false]) do
      {:ok, socket} -> {:ok, %{client | socket: socket}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reconnect_and_call(client, func) do
    case reconnect(client) do
      {:ok, client} ->
        {client, func.(client)}

      {:error, reason} ->
        {client, {:error, reason}}
    end
  end

  defp call_and_reconnect_if_closed(%{socket: nil} = client, func) do
    reconnect_and_call(client, func)
  end

  defp call_and_reconnect_if_closed(client, func) do
    case func.(client) do
      {:error, reason} when reason in [:enotconn, :closed] ->
        reconnect_and_call(client, func)

      result ->
        {client, result}
    end
  end

  defp lookup_error(index) do
    Ownet.ErrorMap.lookup(index)
  end

  # The error map would normally be loaded from the server, but for now we'll just hardcode it.
  # defp load_error_map(client) do
  #  case read_errors(client) do
  #    {:ok, client, codes} ->
  #       {:ok, %{client | errors_map: parse_error_codes(codes)}}
  #    {:error, reason} -> {:error, reason}
  #  end
  # end
  #
  # defp read_errors(client) do
  #  case call_and_reconnect_if_closed(client, fn client ->
  #         Socket.read(client.socket, "/settings/return_codes/text.ALL", client.flags)
  #       end) do
  #    {client, {:ok, value}} -> {:ok, client, value}
  #    {_client, {:error, reason}} -> {:error, reason}
  #  end
  # end

  # defp parse_error_codes(codes) do
  # # Create a lookup map of error codes.
  # # codes= 'Good result,Startup - command line parameters invalid,legacy - No such en opened,...'
  # # res = %{0: "Good result", 1: "Startup - command line parameters invalid", 2: "legacy - No such en opened", ...}
  # codes
  # |> to_string()
  # |> String.split(",")
  # |> Enum.with_index()
  # |> Enum.map(fn {k, v} -> {v, k} end)
  # |> Enum.into(%{})
  # end
end
