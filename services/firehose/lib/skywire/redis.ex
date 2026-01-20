defmodule Skywire.Redis do
  @moduledoc """
  Behaviour and Proxy for Redis Client.
  
  In Test: uses Mock.
  In Prod: uses Skywire.Redis.Real.
  """
  
  @callback command(list(String.t())) :: {:ok, any()} | {:error, any()}
  @callback pipeline(list(list(String.t()))) :: {:ok, list(any())} | {:error, any()}

  def command(args), do: impl().command(args)
  def pipeline(args), do: impl().pipeline(args)

  def child_spec(opts) do
    module = impl()
    
    if function_exported?(module, :child_spec, 1) do
      module.child_spec(opts)
    else
      # If the implementation (e.g. Mock) doesn't need to be started, 
      # we return a dummy child spec that starts a temporary Task which immediately finishes with :ignore.
      # This satisfies the Supervisor that wants to start "Skywire.Redis".
      %{
        id: module,
        start: {Task, :start_link, [fn -> :ignore end]},
        type: :worker,
        restart: :temporary
      }
    end
  end

  defp impl do
    Application.get_env(:skywire, :redis_impl, Skywire.Redis.Real)
  end
end
