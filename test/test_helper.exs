defmodule SocketMock do
  @callback send(:gen_tcp.socket(), binary()) :: :ok | {:error, :inet.posix()}
  @callback recv(:gen_tcp.socket(), integer()) :: {:ok, binary()} | {:error, :inet.posix()}
  @callback close(:gen_tcp.socket()) :: :ok
  @callback connect(charlist, integer, :gen_tcp.opts()) :: {:ok, :gen_tcp.socket()} | {:error, :inet.posix()}
end

Code.put_compiler_option(:ignore_module_conflict, true)
:code.unstick_mod(:gen_tcp)
Mox.defmock(:gen_tcp, for: SocketMock)

ExUnit.start()
