defmodule Exownet do
  defstruct [:address, :port, :flags, :socket, :errors_map]
  use GenServer
  alias Exownet.OWClient
  alias Exownet.Socket

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
    #socket = Socket.connect(address, port, [:binary, active: false])

    {:ok, %__MODULE__{
      address: address,
      port: port,
      flags: flags,
      socket: nil,
      errors_map: %{}
    }}

    #case OWClient.read(socket, "/settings/return_codes/text.ALL", flags) do
    #  {:ok, ret_codes, persistence} ->
    #    state = %__MODULE__{
    #      address: address,
    #      port: port,
    #      flags: flags,
    #      socket: (if persistence, do: socket, else: nil),
    #      errors_map: parse_ret_codes(ret_codes)
    #    }
    #    {:ok, state}
#
    #  {:error, reason, _persistence} when is_integer(reason) ->
    #    {:error, "Unknown error #{reason}"}
#
    #  {_client, :error, reason} ->
    #    {:error, reason}
    #end
  end

  @impl true
  def handle_call({:ping, flags}, _from, state) do
    case do_ping(state, flags++state.flags) do
      {socket, {:ok, persistence}} -> reply(:ok, state, socket, persistence)
      {socket, {:error, reason, persistence}} -> reply({:error, reason}, state, socket, persistence)
      {:error, _reason} -> raise "Connection error"
    end

    #Map.get(state.errors_map, reason, "Unknown error #{reason}")}
  end

  @impl true
  def handle_call({:dir, path, flags}, _form, state) do
    case do_dir(path, state, flags++state.flags) do
      {socket, {:ok, paths, persistence}} -> reply({:ok, paths}, state, socket, persistence)
      {socket, {:error, reason, persistence}} -> reply({:error, reason}, state, socket, persistence)
      {:error, _reason} -> raise "Connection error"
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

  defp do_dir(path, state, flags) do
    case get_socket(state) do
      {:ok, socket} -> {socket, OWClient.dir(socket, path, flags)}
      {:error, reason} -> {:error, reason}
    end
  end


  defp update_socket_state(state, socket, persistence)
  defp update_socket_state(state, socket, true) do
      %{state|socket: socket}
  end

  defp update_socket_state(state, socket, false) do
    Socket.close(socket)
    %{state|socket: nil}
  end

  defp update_socket_state(state, nil, _) do
    %{state|socket: nil}
  end

  defp get_socket(state) when state.socket == nil do
    Socket.connect(state.address, state.port, [:binary, active: false])
  end

  defp get_socket(state) do
    {:ok, state.socket}
  end


  # charlist :: map(integer: string.t)
  defp parse_ret_codes(codes) do
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


#
# @impl true
# def handle_call({:dir, path, flags}, _from, state) do
#   case OWClient.dir(state.client, path, flags) do
#     {client, :ok, values} ->
#       {:reply, {:ok, values}, update_client(state, client)}
#
#     {client, :error, reason} when is_integer(reason) ->
#       {:reply, {:error, Map.get(state.errors_map, reason, "Unknown error #{reason}")}, update_client(state, client)}
#
#     {client, :error, reason} ->
#       {:reply, {:error, reason}, update_socket_state(state, socket, persistence)}
#   end
# end
#
# @impl true
# def handle_call({:read, path, flags}, _from, state) do
#   case OWClient.read(state.client, path, flags) do
#     {client, :ok, values} ->
#       {:reply, {:ok, values}, update_client(state, client)}
#
#     {client, :error, reason} when is_integer(reason) ->
#       {:reply, {:error, Map.get(state.errors_map, reason, "Unknown error #{reason}")}, update_client(state, client)}
#
#     {client, :error, reason} ->
#       {:reply, {:error, reason}, update_socket_state(state, socket, persistence)}
#   end
# end
#
# @impl true
# def handle_call({:write, path, value, flags}, _from, state) do
#   case OWClient.write(state.client, path, value, flags) do
#     {client, :ok} ->
#       {:reply, :ok, update_client(state, client)}
#
#     {client, :error, reason} when is_integer(reason) ->
#       {:reply, {:error, Map.get(state.errors_map, reason, "Unknown error #{reason}")}, update_client(state, client)}
#
#     {client, :error, reason} ->
#       {:reply, {:error, reason}, update_client(state, client)}
#   end
# end
#

  defp parse_float(value) do
    value
    |> String.trim
    |> Float.parse
  end
end
