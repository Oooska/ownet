defmodule Ownet do
  @moduledoc """
  The `Ownet` module provides a client API to interact with an owserver from the OWFS
  (1-Wire file system) family. It provides a set of functions to communicate with
  owserver, making it possible to read, write, and check the presence of paths in the
  1-Wire network.

  It's only been tested against the latest version of owserver - `v3.2p4`.
  """

  defstruct [:address, :port, :flags, :socket, :errors_map]
  use GenServer

  alias Ownet.Client

  @type ownet :: GenServer.server()
  @type error :: {:error, atom()} | {:error, String.t()}

  @doc """
  Starts Ownet with the provided options and links it to the current process.

  To add Ownet to a supervision tree:
  ```elixir
  {Ownet, name: MyOwnet, address: "localhost", port: 4304, flags: [:uncached, :f, :persistence]}
  ```

  ## Options
  - `:address` - The address of the owserver. This can be a charlist or a binary. The default is "localhost".
  - `:port` - The port of the owserver. The default is 4304.
  - `:flags` - A list of flags to apply to every command. See the module documentation for more details on available flags.
  - `:name` - An optional name to register the GenServer under.

  ## Examples

  ```elixir
  Ownet.start_link(name: :ownet, address: "localhost", port: 4304, flags: [:uncached])
  ```
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    address = Keyword.get(opts, :address, ~c"localhost")
    name = Keyword.get(opts, :name)
    server_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, Keyword.put(opts, :address, address), server_opts)
  end

  @doc """
  Sends a ping request to the owserver to check the connection status. Returns :ok on success,
  or an error tuple.

  ## Parameters

  - `opts` - Accepts flags (that don't do anything for a ping command aside from `[:persistence]`)

  ## Examples

  ```elixir
  iex(12)> Ownet.ping(:ownet)
  :ok
  ```
  """
  @spec ping(ownet(), Keyword.t()) :: :ok | error()
  def ping(pid, opts \\ []) do
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(pid, {:ping, flags})
  end

  @doc """
  Checks if a path is present in the 1-Wire network. Returns `{:ok, true}` or
  `{:ok, false}` depending on if the path is present on the 1-Wire bus.

  ## Parameters
  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  ## Examples

  ```elixir
  iex(11)> Ownet.present(:ownet, "/10.F2FBE3467CC2/")
  {:ok, true}
  iex(17)> Ownet.present(:ownet, "/NOTPRESENT/")
  {:ok, false}
  ```
  """
  @spec present(ownet(), String.t(), Keyword.t()) :: {:ok, boolean()} | error()
  def present(pid, path, opts \\ []) do
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(pid, {:present, path, flags})
  end

  @doc """
  Lists the directory at the specified path in the 1-Wire network.

  ## Parameters
  - `path`: A string representing the path in the 1-Wire network. The default is the root ("/").
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  ## Examples

  ```elixir
  iex(2)> Ownet.dir(:ownet, "/")
  {:ok,
    ["/29.67C6697351FF/", "/29.4AEC29CDBAAB/", "/10.F2FBE3467CC2/",
     "/10.54F81BE8E78D/"]}

  iex(3)> Ownet.dir(:ownet, "/", flags: [:bus_ret])
  {:ok,
    ["/29.67C6697351FF/", "/29.4AEC29CDBAAB/", "/10.F2FBE3467CC2/",
     "/10.54F81BE8E78D/", "/bus.1/", "/uncached/", "/settings/", "/system/",
     "/statistics/", "/structure/", "/simultaneous/", "/alarm/"]}

  iex(4)> Ownet.dir(:ownet, "/10.F2FBE3467CC2/")
  {:ok,
    ["/10.F2FBE3467CC2/address", "/10.F2FBE3467CC2/alias", "/10.F2FBE3467CC2/crc8",
     "/10.F2FBE3467CC2/errata/", "/10.F2FBE3467CC2/family", "/10.F2FBE3467CC2/id",
     "/10.F2FBE3467CC2/latesttemp", "/10.F2FBE3467CC2/locator",
     "/10.F2FBE3467CC2/power", "/10.F2FBE3467CC2/r_address",
     "/10.F2FBE3467CC2/r_id", "/10.F2FBE3467CC2/r_locator",
     "/10.F2FBE3467CC2/scratchpad", "/10.F2FBE3467CC2/temperature",
     "/10.F2FBE3467CC2/temphigh", "/10.F2FBE3467CC2/templow",
     "/10.F2FBE3467CC2/type"]}
  ```
  """
  @spec dir(ownet(), String.t(), Keyword.t()) :: {:ok, list(String.t())} | error()
  def dir(pid, path, opts \\ []) do
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(pid, {:dir, path, flags})
  end

  @doc """
  Reads the value at the specified path in the 1-Wire network.

  ## Parameters
  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  ## Examples

  ```elixir
  iex(6)> Ownet.read(:ownet, "/10.F2FBE3467CC2/temperature")
  {:ok, "     85.9296"}
  iex(7)> Ownet.read(:ownet, "/10.F2FBE3467CC2/temperature", flags: [:f])
  {:ok, "     186.6732"}
  iex(8)> Ownet.read(:ownet, "/29.67C6697351FF/PIO.0")
  {:ok, "0"}
  iex(16)> Ownet.read(:ownet, "/10.F2FBE3467CC2/type")
  {:ok, "DS18S20"}
  ```
  """
  @spec read(ownet(), String.t(), Keyword.t()) :: {:ok, binary()} | error()
  def read(pid, path, opts \\ []) do
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(pid, {:read, path, flags}, 25000)
  end

  @doc """
  Reads the value at the specified path in the 1-Wire network, and attempts to convert it to an integer value.
  Floating point values will be truncated. If the value cannot be parsed as an integer, `{:error, :invalid_type}` is returned.

  ## Parameters

  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  ```elixir
  iex(8)> Ownet.read_int(:ownet, "/10.F2FBE3467CC2/temperature")
  {:ok, 88}
  iex(9)> Ownet.read_int(:ownet, "/29.67C6697351FF/PIO.0")
  {:ok, 1}
  iex(15)> Ownet.read_int(:ownet, "/10.F2FBE3467CC2/type")
  {:error, :invalid_type}
  ```
  """
  @spec read_int(ownet(), String.t(), Keyword.t()) :: {:ok, integer()} | error()
  def read_int(pid, path, opts \\ []) do
    read(pid, path, opts)
    |> maybe_parse_int
  end

  @doc """
  Reads the value at the specified path in the 1-Wire network, and attempts to convert it to a floating-point value.

  ## Parameters
  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  ## Examples

  ```elixir
  iex(13)> Ownet.read_float(:ownet, "/10.F2FBE3467CC2/temperature")
  {:ok, 48.4292}
  iex(13)> Ownet.read_float(:ownet, "/10.F2FBE3467CC2/temperature", flags: [:f])
  {:ok, 119.1725}
  iex(14)> Ownet.read_float(:ownet, "/29.67C6697351FF/PIO.0")
  {:ok, 1.0}
  iex(15)> Ownet.read_float(:ownet, "/10.F2FBE3467CC2/type")
  {:error, :invalid_type}
  ```
  """
  @spec read_float(ownet(), String.t(), Keyword.t()) :: {:ok, float()} | error()
  def read_float(pid, path, opts \\ []) do
    read(pid, path, opts)
    |> maybe_parse_float
  end

  @doc """
  Reads the value at the specified path in the 1-Wire network, and attempts to convert
  it to a boolean value. "0", 0, and "false" all convert to :false. "1", 1, and
  "true" all convert to :true. Other values return `{:error, :invalid_type}`.

  ## Parameters
  - `path`: A string representing the path in the 1-Wire network.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  ## Examples
    ```elixir
    iex(14)> Ownet.read_bool(:ownet, "/29.67C6697351FF/PIO.0")
    {:ok, true}
    iex(16)> Ownet.read_bool(:ownet, "/10.F2FBE3467CC2/type")
    {:error, :invalid_type}
    ```
  """
  @spec read_bool(ownet(), String.t(), Keyword.t()) :: {:ok, boolean()} | error()
  def read_bool(pid, path, opts \\ []) do
    with {:ok, value} <- read(pid, path, opts) do
      case value do
        "0" -> {:ok, false}
        "1" -> {:ok, true}
        "false" -> {:ok, false}
        "true" -> {:ok, true}
        <<0>> -> {:ok, false}
        <<1>> -> {:ok, true}
        _ -> {:error, :invalid_type}
      end
    end
  end

  @doc """
  Writes a value to the specified path in the 1-Wire network.

  ## Parameters

  - `path`: A string representing the path in the 1-Wire network.
  - `value`: The value to write. This must be a binary value, or one of the values
    true, :on, false, :off. These convert to "1" and "0" respectively.
  - `opts`: A keyword list of options. It also accepts `:flags` option.

  ## Examples

  ```elixir
  iex(19)> Ownet.write(:ownet, "/29.67C6697351FF/PIO.0", true)
  :ok
  iex(20)> Ownet.write(:ownet, "/29.67C6697351FF/type", "value")
  {:error, "legacy - Not supported"}
  ```
  """
  @spec write(ownet(), String.t(), binary() | String.t() | boolean() | :on | :off, Keyword.t()) ::
          :ok | error()
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

  defp maybe_parse_float({:error, reason}), do: {:error, reason}

  defp maybe_parse_float({:ok, value}) do
    # Converts "        23.5" to 23.5
    case value |> String.trim() |> Float.parse() do
      :error -> {:error, :invalid_type}
      {float, ""} -> {:ok, float}
    end
  end

  defp maybe_parse_int({:error, reason}), do: {:error, reason}

  defp maybe_parse_int({:ok, value}) do
    case value |> String.trim() |> Integer.parse() do
      :error -> {:error, :invalid_type}
      {val, _} -> {:ok, val}
    end
  end
end
