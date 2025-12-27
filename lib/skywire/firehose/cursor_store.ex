defmodule Skywire.Firehose.CursorStore do
  @moduledoc """
  Manages the firehose cursor state.
  
  Provides synchronous, crash-safe cursor operations:
  - Read last cursor on startup
  - Update cursor only after DB transaction commits
  """
  use GenServer
  require Logger
  alias Skywire.Repo
  alias Skywire.Firehose.Cursor

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
  This should only be called after successful persistence.
  """
  def set_cursor(seq) when is_integer(seq) do
    GenServer.call(__MODULE__, {:set_cursor, seq})
  end

  ## Callbacks

  @impl true
  def init(_opts) do
    cursor = load_cursor_from_db()
    Logger.info("CursorStore initialized with cursor: #{cursor}")
    {:ok, %{cursor: cursor}}
  end

  @impl true
  def handle_call(:get_cursor, _from, state) do
    {:reply, state.cursor, state}
  end

  @impl true
  def handle_call({:set_cursor, seq}, _from, state) do
    case update_cursor_in_db(seq) do
      :ok ->
        Logger.debug("Cursor updated to #{seq}")
        {:reply, :ok, %{state | cursor: seq}}

      {:error, reason} ->
        Logger.error("Failed to update cursor: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  ## Private Functions

  defp load_cursor_from_db do
    case Repo.one(Cursor) do
      %Cursor{last_seq: seq} -> seq
      nil -> 0
    end
  end

  defp update_cursor_in_db(seq) do
    case Repo.get(Cursor, true) do
      nil ->
        {:error, :cursor_not_found}

      cursor ->
        cursor
        |> Ecto.Changeset.change(last_seq: seq)
        |> Repo.update()
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
