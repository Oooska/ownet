defmodule Ownet do
  defstruct [:address, :port, :flags, :socket, :errors_map]
  use GenServer
  require Logger

  alias Ownet.Client

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
  - There's a few other available flags that aren't documented due to lack of relevancy. See the Packet source for more info.

  ## Examples
  ```
  # iex(1)> Logger.configure(level: :warn)
  # :ok
  # iex(2)> {:ok, pid} = Ownet.start_link('localhost')
  # {:ok, #PID<0.151.0>}
  # iex(3)> Ownet.dir(pid)
  # {:ok, ["/42.C2D154000000/", "/43.E6ABD6010000/"]}
  # iex(4)> Ownet.dir(pid, "/42.C2D154000000/")
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
  # iex(5)> Ownet.read(pid, "/42.C2D154000000/temperature")
  # {:ok, "      22.625"}
  # iex(6)> Ownet.read_float(pid, "/42.C2D154000000/temperature")
  # {:ok, 22.625}
  # iex(7)> Ownet.read_float(pid, "/42.C2D154000000/temperature", flags: [:f])
  # {:ok, 72.725}
  # iex(8)> Ownet.read(pid, "/42.C2D154000000/PIO.A")
  # {:ok, "1"}
  # iex(9)> Ownet.write(pid, "/42.C2D154000000/PIO.A", false)
  # :ok
  # iex(10)> Ownet.read(pid, "/42.C2D154000000/PIO.A")
  # {:ok, "0"}
  # iex(11)> Ownet.read_bool(pid, "/42.C2D154000000/PIO.A")
  # {:ok, false}
  # iex(12)> Ownet.present(pid, "/42.C2D154000000/")
  # {:ok, true}
  # iex(13)> Ownet.present(pid, "/NOTPRESENT/")
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
  # Client API
  def start_link(opts \\ []) do
    address = Keyword.get(opts, :address, ~c"localhost")
    name = Keyword.get(opts, :name)
    server_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, Keyword.put(opts, :address, address), server_opts)
  end

  @doc """
  Sends a ping request to the owserver to check the connection status. Returns :ok on success, or
  an error tuple.

  ## Params

  - `opts` - Accepts flags (that don't do anything for a ping command aside from `[:persistence]`)
  """
  def ping(pid, opts \\ []) do
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(pid, {:ping, flags})
  end

  @doc """
  Checks if a path is present in the 1-Wire network. Returns `{:ok, true}` or `{:ok, false}` depending on if the path is
  present on the one wire bus.

  ## Params
  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.
  """
  def present(pid, path, opts \\ []) do
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(pid, {:present, path, flags})
  end

  @doc """
  Lists the directory at the specified path in the 1-Wire network.

  ## Params
  - `path`: A string representing the path in the 1-Wire network. The default is the root ("/").
  - `opts`: A keyword list of options. It also accepts `:flags` option.
  """
  @spec dir(String.t(), Keyword.t()) :: {:ok, list(String.t())} | {:error, atom()}
  def dir(pid, path, opts \\ []) do
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(pid, {:dir, path, flags})
  end

  @doc """
  Reads the value at the specified path in the 1-Wire network.

  ## Params
  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  """
  def read(pid, path, opts \\ []) do
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(pid, {:read, path, flags}, 25000)
  end

  @doc """
  Reads the value at the specified path in the 1-Wire network, and attempts to convert it to a floating-point value.

  ## Params

  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  """
  def read_float(pid, path, opts \\ []) do
    with {:ok, value} <- read(pid, path, opts),
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
  def read_bool(pid, path, opts \\ []) do
    with {:ok, value} <- read(pid, path, opts) do
      case value do
        "0" -> {:ok, false}
        "1" -> {:ok, true}
        "false" -> {:ok, false}
        "true" -> {:ok, true}
        <<0>> -> {:ok, false}
        <<1>> -> {:ok, true}
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
  def write(pid, path, value, opts \\ []) do
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(pid, {:write, path, value, flags})
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    address = to_charlist(Keyword.get(opts, :address, ~c"localhost"))
    port = Keyword.get(opts, :port, 4304)
    flags = Keyword.get(opts, :flags, [:persistence])

    {:ok, Client.new(address, port, flags)}
  end


  @impl true
  def handle_call({:ping, flags}, _from, state) do
    {client, ret_val} = Client.ping(state, flags)
    {:reply, ret_val, client}
  end

  @impl true
  def handle_call({:present, path, flags}, _from, state) do
    {client, ret_val} = Client.present(state, path, flags)
    {:reply, ret_val, client}
  end

  @impl true
  def handle_call({:dir, path, flags}, _from, state) do
    {client, ret_val} = Client.dir(state, path, flags)
    {:reply, ret_val, client}
  end

  @impl true
  def handle_call({:read, path, flags}, _from, state) do
    {client, ret_val} = Client.read(state, path, flags)
    {:reply, ret_val, client}
  end

  @impl true
  def handle_call({:write, path, value, flags}, _from, state) do
    {client, ret_val} = Client.write(state, path, value, flags)
    {:reply, ret_val, client}
  end

  @spec parse_float(String.t()) :: {float(), binary()} | :error
  defp parse_float(value) do
    # Converts "        23.5" to 23.5
    value
    |> String.trim()
    |> Float.parse()
  end
end
