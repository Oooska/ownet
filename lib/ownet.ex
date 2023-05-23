defmodule Ownet do
  defstruct [:address, :port, :flags, :socket, :errors_map]
  use GenServer
  require Logger

  alias Ownet.OWClient
  alias Ownet.Socket

  @moduledoc """
  The `Ownet` module provides a client API to interact with an owserver from the OWFS (1-wire file system) family. It
  provides a set of functions to communicate with owserver, making it possible to read, write and check the presence of
  paths in the 1-Wire network.

  ## Client API

  - `start_link/1`: This function starts the GenServer with the provided options and links it to the current process.
  - `ping/1`: This function pings the owserver. It's used to check the connection status.
  - `present/2`: This function checks if a path is present in the 1-Wire network.
  - `dir/2`: This function returns the list of devices or properties for the given path.
  - `read/2`: This function reads the value of a property from a given path.
  - `read_float/2`: This function reads the value of a property as a float from a given path.
  - `read_bool/2`: This function reads the value of a property as a boolean from a given path.
  - `write/3`: This function writes a value to a property at a given path.

  ## Multiple servers
  Multiple processes to communicate with different servers can be specified with the :name option.

  ## Connection
  The Ownet protocol was initially designed to be 'stateless' and would allow only one command per connection. By default, the
  `:persistence` flag is set, which will try and re-use the socket. If the server indicates persistence is not granted, the socket
  is closed and tossed out. The client will attempt to seamlessly reconnect when the next command is issued.

  If persistence is granted, but the socket times out, an error will be returned. Attempting the operation again will create a new
  socket and the operation may succeed.

  ## Errors
  Ownet reads and stores the error codes from owserver at initialization, allowing the client to handle error scenarios appropriately.
  Network socket errors are returned in the form {:error, :inet.posix()}, and usually indicate the server is not reachable  or the
  socket timed out.

  Errors returned from the owserver directly are in the form {:error, String.t()}. These indicate that the client is communicating
  with the owserver, but it did not like the command. The device is no longer being seen by the bus
  ({:error, "Startup - command line parameters invalid"}), device communication error ({:error, "Device - Device name bad CRC8"}),
  or the request was malformed for some reason (e.g. a bug in the library).

  ## Flags
  Flags can be passed during start_link initializing, in which case those flags will be sent with every command.
  Flags can also be specified when sending the command; these will be applied alongside the default ones.
  If you specify multiple conflicting flags (e.g. [:c, :f, :k]), results are unspecified.

  - `:persistence` - Reuse the network socket for multiple commands. This is a default option.
  - `:uncached` - Skips the owfs cache. Default owfs configuration caches responses for ~15 seconds; the flag `:uncached` will force
      owserver to read the value from the sensor. An alternative to using the flag is to prepend "uncached" to a path,
      e.g. `Ownet.read("uncached/42.C2D154000000/temperature")`
  - `:c`, `:f`, `:k`, `:r` - Specifies temperature scale. `:c` is default.
  - `:mbar`, `:atm`, `:mmhg`, `:inhg`, `:psi`  - Specifies pressure scale. `:mbar` is default.
  - `:bus_ret` - Shows 'special' or 'hidden' directories in dir() command responses, such as `/system/`.
  - `:fdi`, `:fi`, `:fdidc`, `:fdic`, `:fidc`, `:fic` - Changes the way one wire addresses are displayed. `:fdi` is default.
  - There's a few other available flags that aren't documented due to lack of relevancy. See the OWPacket source for more info.

  ## Examples
  ```
  # iex(1)> Logger.configure(level: :warn)
  # :ok
  # iex(2)> Ownet.start_link(address: 'localhost')
  # {:ok, #PID<0.151.0>}
  # iex(3)> Ownet.dir()
  # {:ok, ["/42.C2D154000000/", "/43.E6ABD6010000/"]}
  # iex(4)> Ownet.dir("/42.C2D154000000/")
  # {:ok,
  # ["/42.C2D154000000/PIO.BYTE", "/42.C2D154000000/PIO.ALL",
  #   "/42.C2D154000000/PIO.A", "/42.C2D154000000/PIO.B",
  #   "/42.C2D154000000/address", "/42.C2D154000000/alias", "/42.C2D154000000/crc8",
  #   "/42.C2D154000000/family", "/42.C2D154000000/fasttemp", "/42.C2D154000000/id",
  #   "/42.C2D154000000/latch.BYTE", "/42.C2D154000000/latch.ALL",
  #   "/42.C2D154000000/latch.A", "/42.C2D154000000/latch.B",
  #   "/42.C2D154000000/latesttemp", "/42.C2D154000000/locator",
  #   "/42.C2D154000000/power", "/42.C2D154000000/r_address",
  #   "/42.C2D154000000/r_id", "/42.C2D154000000/r_locator",
  #   "/42.C2D154000000/sensed.BYTE", "/42.C2D154000000/sensed.ALL",
  #   "/42.C2D154000000/sensed.A", "/42.C2D154000000/sensed.B",
  #   "/42.C2D154000000/temperature", "/42.C2D154000000/temperature10",
  #   "/42.C2D154000000/temperature11", "/42.C2D154000000/temperature12",
  #   "/42.C2D154000000/temperature9", "/42.C2D154000000/tempres",
  #   "/42.C2D154000000/type"]}
  # iex(5)> Ownet.read("/42.C2D154000000/temperature")
  # {:ok, "      22.625"}
  # iex(6)> Ownet.read_float("/42.C2D154000000/temperature")
  # {:ok, 22.625}
  # iex(7)> Ownet.read_float("/42.C2D154000000/temperature", flags: [:f])
  # {:ok, 72.725}
  # iex(8)> Ownet.read("/42.C2D154000000/PIO.A")
  # {:ok, "1"}
  # iex(9)> Ownet.write("/42.C2D154000000/PIO.A", false)
  # :ok
  # iex(10)> Ownet.read("/42.C2D154000000/PIO.A")
  # {:ok, "0"}
  # iex(11)> Ownet.read_bool("/42.C2D154000000/PIO.A")
  # {:ok, false}
  # iex(12)> Ownet.present("/42.C2D154000000/")
  # {:ok, true}
  # iex(13)> Ownet.present("/NOTPRESENT/")
  # {:ok, false}


  # You can tell all the powered temperature sensors to start reading all of the powered
  # temperature sensors simultaneously, and then read them quickly without waiting for the
  # analog-to-digital conversion:

  # iex(14)> Ownet.write("/simultaneous/temperature", true)
  # :ok

  # Wait ~0.75 seconds

  # iex(15)> Ownet.read("uncached/42.C2D154000000/latesttemp")
  # {:ok, "     22.1875"}
  ```

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

  @doc """
  Sends a ping request to the owserver to check the connection status. Returns :ok on success, or
  an error tuple.

  ## Params

  - `opts` - Accepts flags (that don't do anything for a ping command aside from `[:persistence]`)
  """
  def ping(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:ping, flags})
  end

  @doc """
  Checks if a path is present in the 1-Wire network. Returns `{:ok, true}` or `{:ok, false}` depending on if the path is
  present on the one wire bus.

  ## Params
  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.
  """
  def present(path, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:present, path, flags})
  end

  @doc """
  Lists the directory at the specified path in the 1-Wire network.

  ## Params
  - `path`: A string representing the path in the 1-Wire network. The default is the root ("/").
  - `opts`: A keyword list of options. It also accepts `:flags` option.
  """
  @spec dir(String.t(), Keyword.t()) :: {:ok, list(String.t())} | {:error, atom()}
  def dir(path \\ "/", opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:dir, path, flags})
  end

  @doc """
  Reads the value at the specified path in the 1-Wire network.

  ## Params

  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  """
  def read(path, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:read, path, flags}, 25000)
  end

  @doc """
  Reads the value at the specified path in the 1-Wire network, and attempts to convert it to a floating-point value.

  ## Params

  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  """
  def read_float(path, opts \\ []) do
    with {:ok, value} <- read(path, opts),
         {float, _} <- parse_float(value) do
          {:ok, float}
    else
      :error -> {:error, "Not a float"}
      error -> error
    end
  end

    @doc """
    Reads the value at the specified path in the 1-Wire network, and attempts to convert it to a boolean value.
    "0", 0, and "false" all convert to :false. "1", 1, and "true" all convert to :true. Other values return `{:error, "Not a boolean"}`

    ## Params

    - `path`: A string representing the path in the 1-Wire network.
    - `opts`: A keyword list of options. It also accepts `:flags` option.

  """
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

  @doc """
  Writes a value to the specified path in the 1-Wire network.

  ## Params

  - `path`: A string representing the path in the 1-Wire network.
  - `value`: The value to write. This must be a binary value, or one of the values true, :on, false, :off.
      These convert to "1" and "0" respectively.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  """
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
    flags = Keyword.get(opts, :flags, [:persistence])

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

  @spec parse_float(String.t()) :: float() | :error
  defp parse_float(value) do
    #Converts "        23.5" to 23.5
    value
    |> String.trim
    |> Float.parse
  end
end
