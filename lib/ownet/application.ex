defmodule Ownet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    #children = [
      # Starts a worker by calling: MyApp.Worker.start_link(arg)
      # {MyApp.Worker, arg}
      {DynamicSupervisor, strategy: :one_for_one, name: Ownet.DynamicSupervisor}
    #]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: __MODULE__]
    DynamicSupervisor.start_link(opts)
  end

  @spec start_client(any) :: :ignore | {:error, any} | {:ok, pid} | {:ok, pid, any}
  def start_client(opts) do
    DynamicSupervisor.start_child(__MODULE__, Ownet.child_spec(opts))
  end
end
