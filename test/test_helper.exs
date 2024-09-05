defmodule GenTCPMock do
  @callback send(:gen_tcp.socket(), binary()) :: :ok | {:error, :inet.posix()}
  @callback recv(:gen_tcp.socket(), integer()) :: {:ok, binary()} | {:error, :inet.posix()}
  @callback close(:gen_tcp.socket()) :: :ok
  @callback connect(charlist, integer, :gen_tcp.opts()) :: {:ok, :gen_tcp.socket()} | {:error, :inet.posix()}
end

defmodule SocketMock do
  @callback ping(:gen_tcp.socket(), Packet.flag_list()) :: :ok | {:error, :inet.posix()}
  @callback present(:gen_tcp.socket(), String.t(), Packet.flag_list()) :: {:ok, boolean()} | {:error, :inet.posix()}
  @callback dir(:gen_tcp.socket(), String.t(), Packet.flag_list()) :: {:ok, list(String.t())} | {:error, :inet.posix()}
  @callback read(:gen_tcp.socket(), String.t(), Packet.flag_list()) :: {:ok, binary()} | {:error, :inet.posix()}
  @callback write(:gen_tcp.socket(), String.t(), binary(), Packet.flag_list()) :: :ok | {:error, :inet.posix()}
end


Code.put_compiler_option(:ignore_module_conflict, true)
:code.unstick_mod(:gen_tcp)
#Mox.defmock(:gen_tcp, for: GenTCPMock)

ExUnit.start()
