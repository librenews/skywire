defmodule Skywire.Firehose.Processor do
  @moduledoc """
  Handles batched processing of firehose events.
  
  Events are buffered in memory and flushed to the database in batches
  to handle high throughput (thousands of events/sec).
  
  Batch flush triggers:
  - 500 events accumulated OR
  - 100ms elapsed (whichever happens first)
  
  If buffer reaches max capacity, the process crashes intentionally
  and supervisor restarts it.
  """
  use GenServer
  require Logger
  alias Skywire.Repo
  alias Skywire.Firehose.{Event, CursorStore}

  @batch_size 500
  @flush_interval_ms 100
  @max_buffer_size 2000

  defmodule State do
    defstruct buffer: [],
              buffer_size: 0,
              flush_timer: nil
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Process a single event from the firehose.
  """
  def process_event(event) do
    GenServer.cast(__MODULE__, {:process_event, event})
  end

  ## Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Firehose.Processor started")
    {:ok, %State{}}
  end

  @impl true
  def handle_cast({:process_event, event}, state) do
    new_buffer = [event | state.buffer]
    new_size = state.buffer_size + 1

    # Check if we've exceeded max buffer size (backpressure failure)
    if new_size > @max_buffer_size do
      Logger.error("Buffer overflow! Size: #{new_size}. Crashing to trigger restart.")
      raise "Buffer overflow - database writes too slow"
    end

    # Start flush timer if not already running
    timer = state.flush_timer || schedule_flush()

    new_state = %{state | buffer: new_buffer, buffer_size: new_size, flush_timer: timer}

    # Flush if batch size reached
    if new_size >= @batch_size do
      flush_buffer(new_state)
      {:noreply, %State{}}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    if state.buffer_size > 0 do
      flush_buffer(state)
      {:noreply, %State{}}
    else
      {:noreply, %{state | flush_timer: nil}}
    end
  end

  ## Private Functions

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end

  defp flush_buffer(state) do
    events = Enum.reverse(state.buffer)
    Logger.info("Flushing buffer with #{length(events)} events")
    
    case persist_batch(events) do
      {:ok, max_seq} ->
        Logger.debug("Flushed #{length(events)} events, max_seq: #{max_seq}")
        :ok = CursorStore.set_cursor(max_seq)
        Logger.info("Dispatching events to LinkDetector...")
        Skywire.LinkDetector.dispatch_batch(events)
        
      {:error, reason} ->
        Logger.error("Failed to persist batch: #{inspect(reason)}")
        # Crash to trigger restart and replay from last cursor
        raise "Batch persistence failed: #{inspect(reason)}"
    end
  end

  defp persist_batch(events) do
    Repo.transaction(fn ->
      # Insert all events in a single batch
      entries = Enum.map(events, fn event ->
        %{
          seq: event.seq,
          repo: event.repo,
          event_type: event.event_type,
          collection: event.collection,
          record: event.record,
          indexed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      end)

      Repo.insert_all(Event, entries, on_conflict: :nothing)

      # Return the maximum seq from this batch
      Enum.max_by(events, & &1.seq).seq
    end)
  end
end
