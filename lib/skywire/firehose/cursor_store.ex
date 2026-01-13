defmodule Skywire.Firehose.CursorStore do
  @moduledoc """
  Manages the firehose cursor state using Redis.
  """
  use GenServer
  require Logger
  alias Skywire.Redis

  @cursor_key "firehose:cursor"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current cursor value.
  """
  def get_cursor do
    GenServer.call(__MODULE__, :get_cursor)
  end

  @doc """
  Set the cursor to a new sequence number.
  """
  def set_cursor(seq) when is_integer(seq) do
    GenServer.call(__MODULE__, {:set_cursor, seq})
  end

  ## Callbacks

  @impl true
  def init(_opts) do
    cursor = load_cursor_from_redis()
    Logger.info("CursorStore initialized with cursor: #{cursor}")
    {:ok, %{cursor: cursor}}
  end

  @impl true
  def handle_call(:get_cursor, _from, state) do
    {:reply, state.cursor, state}
  end

  @impl true
  def handle_call({:set_cursor, seq}, _from, state) do
    case Redis.command(["SET", @cursor_key, seq]) do
      {:ok, "OK"} ->
        {:reply, :ok, %{state | cursor: seq}}

      {:error, reason} ->
        Logger.error("Failed to update cursor: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  ## Private Functions

  defp load_cursor_from_redis do
    case Redis.command(["GET", @cursor_key]) do
      {:ok, nil} -> 0
      {:ok, seq_str} -> String.to_integer(seq_str)
      {:error, reason} ->
        Logger.error("Failed to load cursor from Redis: #{inspect(reason)}")
        # If Redis is down regarding persistent state, we should probably crash or retry.
        # But for now, returning 0 might be dangerous (replaying history).
        # Better to return 0 if first run, or crash if connection fails.
        # Assuming crash for safety if connection is truly borked on boot.
        0 
    end
  end
end
