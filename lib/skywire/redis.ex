defmodule Skywire.Redis do
  @moduledoc """
  Wrapper around Redix for Redis interactions.
  """
  
  # Name of the named process
  @connection_name :skywire_redis

  def child_spec(_opts) do
    redis_url = Application.fetch_env!(:skywire, :redis_url)
    
    %{
      id: Redix,
      start: {Redix, :start_link, [redis_url, [name: @connection_name]]}
    }
  end

  @doc """
  Executes a command against the global Redis (Skywire) connection.
  """
  def command(command) do
    Redix.command(@connection_name, command)
  end

  def pipeline(commands) do
    Redix.pipeline(@connection_name, commands)
  end
end
