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

  @batch_size 256
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
         # Calculate Lag
         avg_lag_sec = calculate_lag(events)
         Logger.info("Indexed #{length(events)} events to OpenSearch (Lag: #{avg_lag_sec}s)")
         
         # 3. Update Cursor
         max_seq = Enum.max_by(events, & &1.seq).seq
         :ok = CursorStore.set_cursor(max_seq)
         
         # 4. Dispatch to downstream consumers
         Skywire.LinkDetector.dispatch_batch(events)
         Skywire.Matcher.check_matches(events_with_embeddings)
         broadcast_to_previews(events_with_embeddings)
         
      {:error, :circuit_breaker} ->
         # Pause and die to allow backoff
         Logger.error("OpenSearch Circuit Breaker tripped. Dropping batch and restarting.")
         raise "OpenSearch Circuit Breaker (OOM)"

      {:error, reason} ->
         Logger.error("Failed to index batch to OpenSearch: #{inspect(reason)}")
         raise "OpenSearch indexing failed: #{inspect(reason)}"
    end
  end

  defp generate_embeddings_for_batch(events) do
    # 1. Filter events that have valid text AND are in a supported language (currently only "en")
    valid_events_with_indices = 
      events
      |> Enum.with_index()
      |> Enum.filter(fn {event, _idx} -> has_valid_text_and_language?(event) end)

    if valid_events_with_indices == [] do
      Enum.map(events, &{&1, nil})
    else
      # 2. Group by language to choose the right model
      # Currently we only support "en", but this structure supports expansion.
      # Since we already filtered for supported languages, we can just group.
      
      grouped_by_lang = 
        valid_events_with_indices
        |> Enum.group_by(fn {event, _} -> get_primary_language(event) end)

      # 3. Generate embeddings for each language group
      # We accumulate all results into a single map of {index => embedding}
      embedding_map = 
        Enum.reduce(grouped_by_lang, %{}, fn {lang, group}, acc ->
          texts = Enum.map(group, fn {event, _} -> get_text(event) end)
          Logger.info("Generating embeddings for #{length(texts)} events (Language: #{lang})...")
          
          # Use Local ML
          case Skywire.ML.Local.generate_batch(texts) do
            nil -> acc # Failed or skipped
            embeddings when is_list(embeddings) ->
              # Map local group indices to embeddings
              group
              |> Enum.zip(embeddings)
              |> Enum.reduce(acc, fn {{_event, original_idx}, emb}, map_acc ->
                Map.put(map_acc, original_idx, emb)
              end)
            _ -> acc
          end
        end)

      # 4. Merge results back into original event list
      events
      |> Enum.with_index()
      |> Enum.map(fn {event, idx} -> 
        {event, Map.get(embedding_map, idx)}
      end)
    end
  end

  defp has_valid_text_and_language?(event) do
    collection = Map.get(event, :collection) || Map.get(event, "collection")
    
    if collection == "app.bsky.feed.post" do
      text = get_text(event)
      langs = get_langs(event)
      
      # Check if text is substantial AND language is English
      # If 'langs' is empty/nil, we might default to false or true? 
      # Bluesky usually populates it. Let's be strict: must include "en".
      is_english = langs && "en" in langs
      
      text && String.length(text) > 10 && is_english
    else
      false
    end
  end

  defp get_text(event) do
    record = Map.get(event, :record) || Map.get(event, "record") || %{}
    Map.get(record, "text")
  end
  
  defp get_langs(event) do
    record = Map.get(event, :record) || Map.get(event, "record") || %{}
    Map.get(record, "langs") # Returns list of strings e.g. ["en"]
  end
  
  defp get_primary_language(_event) do
    # For now, just take "en" if present, or the first one.
    # Since we filtered `has_valid_text_and_language?`, we know "en" is in there.
    "en"
  end

  defp calculate_lag([]), do: 0.0
  defp calculate_lag(events) do
    now = DateTime.utc_now()
    
    # Take the latest event time to see how far behind "real-time" we are
    # Event "time" is usually microseconds or ISO string? 
    # Let's inspect get_time in a bit, but assuming we can parse it.
    
    # Actually, let's just use the first event in the reversed list (which is the newest)
    latest_event = hd(events)
    event_time = get_event_time(latest_event)
    
    if event_time do
      DateTime.diff(now, event_time, :millisecond) / 1000.0
    else
      0.0
    end
  end

  defp get_event_time(event) do
    # In our Connection.ex, we map Jetstream 'time_us' to the :seq field.
    # So :seq IS the timestamp in microseconds.
    
    seq = Map.get(event, :seq) || Map.get(event, "seq")
    
    case seq do
      us when is_integer(us) -> DateTime.from_unix(us, :microsecond) |> elem(1)
      # Fallback to :time if seq isn't a timestamp (legacy?)
      _ -> 
         time_us = Map.get(event, :time) || Map.get(event, "time")
         if is_integer(time_us), do: DateTime.from_unix(time_us, :microsecond) |> elem(1), else: nil
    end
  end

  defp broadcast_to_previews(events_with_embeddings) do
    Phoenix.PubSub.broadcast(Skywire.PubSub, "firehose", {:new_embeddings, events_with_embeddings})
  end
end
