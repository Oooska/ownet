defmodule Exownet do
  defstruct [:client, :errors_map]
  use GenServer
  alias Exownet.OWClient

  @moduledoc """
  Documentation for `Exownet`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Exownet.hello()
      :world

  """

  # Client API
  def start(address \\ 'localhost', port \\ 4304, flags \\ [:persistence, :uncached], opts \\ [])
  def start(address, port, flags, opts) do
    start_link([address: address, port: port, flags: flags] ++ opts)
  end

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def ping(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    flags = Keyword.get(opts, :flags, [])
    GenServer.call(name, {:ping, flags})
  end

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
        <<?0>> -> {:ok, false}
        <<?1>> -> {:ok, true}
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
    flags = Keyword.get(opts, :flags, [])
    client = OWClient.new(address, port, flags)

    with {:ok, client, error_payload} <- OWClient.read(client, "/settings/return_codes/text.ALL") do
      state = %__MODULE__{
        client: client,
        errors_map: parse_error_codes(error_payload)
      }

      {:ok, state}
    else
      {:error, reason} when is_integer(reason) ->
        {:reply, {:error, "Unknown error #{reason}"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_call({:ping, flags}, _from, exownet) do
    case OWClient.ping(exownet.client, flags) do
      {:ok, updated_client} ->
        {:reply, :ok, %{exownet | client: updated_client}}

      {:error, reason} when is_integer(reason) ->
        {:reply, {:error, Map.get(exownet.errors_map, reason, "Unknown error #{reason}")}, exownet}

      {:error, reason} ->
        {:reply, {:error, reason}, exownet}
    end
  end

  @impl true
  def handle_call({:dir, path, flags}, _from, exownet) do
    case OWClient.dir(exownet.client, path, flags) do
      {:ok, updated_client, values} ->
        {:reply, {:ok, values}, %{exownet | client: updated_client}}

      {:error, reason} when is_integer(reason) ->
        {:reply, {:error, Map.get(exownet.errors_map, reason, "Unknown error #{reason}")}, exownet}

      {:error, reason} ->
        {:reply, {:error, reason}, exownet}
    end
  end

  @impl true
  def handle_call({:read, path, flags}, _from, exownet) do
    case OWClient.read(exownet.client, path, flags) do
      {:ok, updated_client, values} ->
        {:reply, {:ok, values}, %{exownet | client: updated_client}}

      {:error, reason} when is_integer(reason) ->
        {:reply, {:error, Map.get(exownet.errors_map, reason, "Unknown error #{reason}")}, exownet}

      {:error, reason} ->
        {:reply, {:error, reason}, exownet}
    end
  end

  @impl true
  def handle_call({:write, path, value, flags}, _from, exownet) do
    case OWClient.write(exownet.client, path, value, flags) do
      {:ok, updated_client, values} ->
        {:reply, {:ok, values}, %{exownet | client: updated_client}}

      {:error, reason} when is_integer(reason) ->
        {:reply, {:error, Map.get(exownet.errors_map, reason, "Unknown error #{reason}")}, exownet}

      {:error, reason} ->
        {:reply, {:error, reason}, exownet}
    end
  end

  defp parse_float(value) do
    value
    |> String.trim
    |> Float.parse
  end


  # charlist :: map(integer: string.t)
  defp parse_error_codes(codes) do
    # Create a lookup map of error codes.
    # codes= 'Good result,Startup - command line parameters invalid,legacy - No such en opened,...'
    # res = %{0: "Good result", 1: "Startup - command line parameters invalid", 2: "legacy - No such en opened", ...}
    codes
    |> to_string()
    |> String.split(",")
    # |> Enum.flat_map(&(String.split(&1, "\n"))) #Not sure why \n was appearing in error codes, it shouldn't be there.
    |> Enum.with_index()
    |> Enum.map(fn {k, v} -> {v, k} end)
    |> Enum.into(%{})
  end
end
