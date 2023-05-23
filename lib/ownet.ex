defmodule Ownet do
  defstruct [:address, :port, :flags, :socket, :errors_map]
  use GenServer
  require Logger

  alias Ownet.OWClient
  alias Ownet.Socket

  @moduledoc """
  Documentation for `Ownet`.

  ## Examples
  """


  @type t :: %__MODULE__{
    address: charlist(),
    port: integer(),
    flags: OWPacket.flag_list(),
    socket: :gen_tcp.socket() | nil,
    errors_map: %{integer() => String.t()}
  }

  @error_codes_path "/settings/return_codes/text.ALL"

  # Client API

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def ping(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:ping, flags})
  end

  def present(path, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:present, path, flags})
  end

  @spec dir(String.t(), Keyword.t()) :: {:ok, list(String.t())} | {:error, atom()}
  def dir(path \\ "/", opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:dir, path, flags})
  end

  def read(path, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:read, path, flags}, 25000)
  end

  def read_float(path, opts \\ []) do
    with {:ok, value} <- read(path, opts),
         {float, _} <- parse_float(value) do
          {:ok, float}
    else
      :error -> {:error, "Not a float"}
      error -> error
    end
  end

  def read_bool(path, opts \\ []) do
    with {:ok, value} <- read(path, opts) do
      case value do
        "0" -> {:ok, false}
        0 -> {:ok, false}
        "1" -> {:ok, true}
        1 -> {:ok, true}
        "false" -> {:ok, false}
        "true" -> {:ok, true}
        _ -> {:error, "Not a boolean"}
      end
    end
  end

  def write(path, value, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:write, path, value, flags})
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    address = to_charlist(Keyword.get(opts, :address, 'localhost'))
    port = Keyword.get(opts, :port, 4304)
    flags = Keyword.get(opts, :flags, [:persistence, :uncached])

    state = %__MODULE__{
      address: address,
      port: port,
      flags: flags,
      socket: nil,
      errors_map: %{}
    }

    case read_error_codes(state) do
      {:ok, state} -> {:ok, state}
      {:ownet_error, reason, state} -> {:ok, state}
        Logger.error("Unable to read error status codes: #{reason}")
      {:error, reason} ->
        Logger.error("Unable to connect to connect to owserver: #{reason}")
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:ping, flags}, _from, state) do
    case do_ping(state, flags ++ state.flags) do
      {socket, {:ok, persistence}} -> reply(:ok, state, socket, persistence)
      {socket, {:ownet_error, reason, persistence}} -> reply({:error, reason}, state, socket, persistence)
      {:error, reason} -> reply({:error, reason}, state, nil, false)
    end
  end

  @impl true
  def handle_call({:present, path, flags}, _from, state) do
    case do_present(state, path, flags ++ state.flags) do
      {socket, {:ok, present, persistence}} -> reply({:ok, present}, state, socket, persistence)
      {:error, reason} -> reply({:error, reason}, state, nil, false)
    end
  end

  @impl true
  def handle_call({:dir, path, flags}, _from, state) do
    case do_dir(path, state, flags ++ state.flags) do
      {socket, {:ok, paths, persistence}} -> reply({:ok, paths}, state, socket, persistence)
      {socket, {:ownet_error, reason, persistence}} -> reply({:error, lookup_error(state, reason)}, state, socket, persistence)
      {:error, reason} -> reply({:error, reason}, state, nil, false)
    end
  end

  @impl true
  def handle_call({:read, path, flags}, _from, state) do
    case do_read(path, state, flags ++ state.flags) do
      {socket, {:ok, value, persistence}} -> reply({:ok, value}, state, socket, persistence)
      {socket, {:ownet_error, reason, persistence}} -> reply({:error, lookup_error(state, reason)}, state, socket, persistence)
      {:error, reason} -> reply({:error, reason}, state, nil, false)
    end
  end

  @impl true
  def handle_call({:write, path, value, flags}, _from, state) do
    case do_write(path, state, value, flags ++ state.flags) do
      {socket, {:ok, persistence}} -> reply(:ok, state, socket, persistence)
      {socket, {:ownet_error, reason, persistence}} -> reply({:error, lookup_error(state, reason)}, state, socket, persistence)
      {:error, reason} -> reply({:error, reason}, state, nil, false)
    end
  end

  defp reply(value, state, socket, persistence) do
    {:reply, value, update_socket_state(state, socket, persistence)}
  end

  defp do_ping(state, flags) do
    case get_socket(state) do
      {:ok, socket} -> {socket, OWClient.ping(socket, flags)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_present(state, path, flags) do
    case get_socket(state) do
      {:ok, socket} -> {socket, OWClient.present(socket, path, flags)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_dir(path, state, flags) do
    case get_socket(state) do
      {:ok, socket} -> {socket, OWClient.dir(socket, path, flags)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_read(path, state, flags) do
    case get_socket(state) do
      {:ok, socket} -> {socket, OWClient.read(socket, path, flags)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_write(path, state, value, flags) do
    case get_socket(state) do
      {:ok, socket} -> {socket, OWClient.write(socket, path, value, flags)}
      {:error, reason} -> {:error, reason}
    end
  end

  #ownet sockets may close randomly; the persistence flag in the header
  #indicates whether the server will keep the socket open.
  #update_socket_state takes the state, the socket, and whether the
  #persistence flag was set, and updates the state with the socket, or closes
  #the socket and sets it to nil.
  defp update_socket_state(state, socket, persistence?)
  defp update_socket_state(state, nil, _) do
    %{state|socket: nil}
  end
  defp update_socket_state(state, socket, true) do
      %{state|socket: socket}
  end

  defp update_socket_state(state, socket, false) do
    Socket.close(socket)
    %{state|socket: nil}
  end

  #ownet sockets might close randomly, so a nil socket is not an error condition.
  #get_socket returns the state's socket if it's connected, otherwise opens a new
  #socket to the server.
  defp get_socket(state) when state.socket == nil do
    Socket.connect(state.address, state.port, [:binary, active: false])
  end

  defp get_socket(state) do
    {:ok, state.socket}
  end


  #ownet returns an integer error code when a command is invalid. This integer code corresponds to
  #the index of a list of errors that can be retrieved by reading "/settings/return_codes/text.ALL"
  #This is attempted in init and stored in errors_map;
  @spec read_error_codes(t()) :: {:ok, t()} | {:ownet_error, integer(), t()} | {:error, :inet.posix()}
  defp read_error_codes(state) do
    case do_read(@error_codes_path, state, []) do
      {socket, {:ok, value, persistence}} ->
        state_with_errors = %{state|errors_map: parse_error_codes(value)}
        {:ok, update_socket_state(state_with_errors, socket, persistence)}
      {socket, {:ownet_error, reason, persistence}} ->
        {:ownet_error, reason, update_socket_state(state, socket, persistence)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lookup_error(state, index) do
    Map.get(state.errors_map, index, "Unknown error: #{index}")
  end

  defp parse_error_codes(codes) do
    # Create a lookup map of error codes.
    # codes= 'Good result,Startup - command line parameters invalid,legacy - No such en opened,...'
    # res = %{0: "Good result", 1: "Startup - command line parameters invalid", 2: "legacy - No such en opened", ...}
    codes
    |> to_string()
    |> String.split(",")
    |> Enum.with_index()
    |> Enum.map(fn {k, v} -> {v, k} end)
    |> Enum.into(%{})
  end

  defp parse_float(value) do
    #Converts "        23.5" to 23.5
    value
    |> String.trim
    |> Float.parse
  end
end
