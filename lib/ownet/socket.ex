defmodule Ownet.Socket do
  #Behaviour wrapper around :gen_tcp so it can be more easily mocked.
  @callback send(:gen_tcp.socket(), binary()) :: :ok | {:error, :inet.posix()}
  @callback recv(:gen_tcp.socket(), integer()) :: {:ok, binary()} | {:error, :inet.posix()}
  @callback close(:gen_tcp.socket()) :: :ok
  @callback connect(charlist, integer, :gen_tcp.opts()) :: {:ok, :gen_tcp.socket()} | {:error, :inet.posix()}

  @spec send(:gen_tcp.socket(), binary()) :: :ok | {:error, :inet.posix()}
  def send(socket, data), do: impl().send(socket, data)

  @spec recv(:gen_tcp.socket(), integer()) :: {:ok, binary()} | {:error, :inet.posix()}
  def recv(socket, num_bytes), do: impl().recv(socket, num_bytes)

  @spec close(:gen_tcp.socket()) :: :ok
  def close(socket), do: impl().close(socket)

  @spec connect(charlist, integer, :gen_tcp.opts()) :: {:ok, :gen_tcp.socket()} | {:error, :inet.posix()}
  def connect(addr, port, opts), do: impl().connect(addr, port, opts)

  defp impl, do: Application.get_env(:Ownet, :socket, :gen_tcp)
end
