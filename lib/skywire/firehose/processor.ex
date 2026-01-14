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
  alias Skywire.Firehose.CursorStore

  @batch_size 25
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
      # Logger.error("Buffer overflow! Size: #{new_size}. Crashing to trigger restart.")
      # Instead of crashing, let's drop the oldest? No, crashing is safer for now.
      # But frequent crashes might be bad.
      # Let's drop if > max
      # Actually, crashing allows the supervisor to backoff.
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
    # Enrich with timestamp immediately
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    
    events = 
      state.buffer
      |> Enum.reverse()
      |> Enum.map(fn e -> Map.put(e, :indexed_at, now) end)

    # 1. Analyze texts & Generate Embeddings
    # We do this FIRST so we can index the complete document
    Logger.info("Generating embeddings for #{length(events)} events...")
    events_with_embeddings = generate_embeddings_for_batch(events)
    Logger.info("Embeddings generated.")
    
    # 2. Index to OpenSearch
    Logger.info("Indexing to OpenSearch...")
    case Skywire.Search.OpenSearch.bulk_index(events_with_embeddings) do
      {:ok, _resp} ->
         Logger.info("Indexed #{length(events)} events to OpenSearch")
         
         # 3. Update Cursor
         max_seq = Enum.max_by(events, & &1.seq).seq
         :ok = CursorStore.set_cursor(max_seq)
         
         # 4. Dispatch to downstream consumers
         Skywire.LinkDetector.dispatch_batch(events)
         Skywire.Matcher.check_matches(events_with_embeddings)
         broadcast_to_previews(events_with_embeddings)
         
      {:error, reason} ->
         Logger.error("Failed to index batch to OpenSearch: #{inspect(reason)}")
         raise "OpenSearch indexing failed: #{inspect(reason)}"
    end
  end

  defp generate_embeddings_for_batch(events) do
    # Filter for valid text
    # We want to keep ALL events for the index (even without text/embedding), 
    # but only generate embeddings for those with text.
    
    # Extract texts where available
    texts_and_indices = 
      events
      |> Enum.with_index()
      |> Enum.filter(fn {event, _idx} -> has_valid_text?(event) end)
      
    if texts_and_indices == [] do
      # No text to embed, return events with nil embeddings
      Enum.map(events, &{&1, nil})
    else
      texts = Enum.map(texts_and_indices, fn {event, _} -> get_text(event) end)
      
      # Generate batch embeddings
      # Note: If batch size is 100, this might be slightly large for one call?
      # Nx.Serving handles batching internally, so it's fine.
      embeddings = Skywire.ML.Embedding.generate_batch(texts, :ingest)
      
      # Create a map of index -> embedding
      embedding_map = 
        Enum.zip(texts_and_indices, embeddings)
        |> Map.new(fn {{_, idx}, emb} -> {idx, emb} end)
        
      # Merge back
      events
      |> Enum.with_index()
      |> Enum.map(fn {event, idx} -> 
        {event, Map.get(embedding_map, idx)}
      end)
    end
  end

  defp has_valid_text?(event) do
    collection = Map.get(event, :collection) || Map.get(event, "collection")
    if collection == "app.bsky.feed.post" do
      text = get_text(event)
      text && String.length(text) > 10 # Only embed posts with some substance
    else
      false
    end
  end

  defp get_text(event) do
    record = Map.get(event, :record) || Map.get(event, "record") || %{}
    Map.get(record, "text")
  end

  defp broadcast_to_previews(events_with_embeddings) do
    Phoenix.PubSub.broadcast(Skywire.PubSub, "firehose", {:new_embeddings, events_with_embeddings})
  end
end
