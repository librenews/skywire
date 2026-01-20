defmodule Skywire.LinkDetector do
  @moduledoc """
  Detects URLs in firehose events and broadcasts them.

  Works on `app.bsky.feed.post` and `app.bsky.feed.repost` events.
  Uses an ETS table to cache links for repost look‑ups.
  """

  use GenServer
  require Logger

  @ets_table :post_links

  # Public API -------------------------------------------------------
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Accept a list of events for efficiency
  def dispatch_batch(events) when is_list(events) do
    GenServer.cast(__MODULE__, {:dispatch_batch, events})
  end

  def dispatch(event) do
    GenServer.cast(__MODULE__, {:dispatch_batch, [event]})
  end

  # -----------------------------------------------------------------
  @impl true
  def init(_state) do
    # Create a named ETS table for fast repost lookup
    :ets.new(@ets_table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:dispatch_batch, events}, state) do
    # Process batch
    Enum.each(events, &process_event/1)
    {:noreply, state}
  end
  
  def handle_cast(_msg, state), do: {:noreply, state}

  defp process_event(event) do
    # Handle both map entries (from Firehose) and structs (from DB)
    # type = Map.get(event, :event_type) || Map.get(event, "event_type") # No longer needed
    
    # We only care about commit events which usually have a type
    # But strictly speaking, the firehose stream sets $type on the message, 
    # which Connection.ex maps to :event_type.
    # The actual post type (app.bsky.feed.post) is inside the record's $type usually?
    # Actually Connection.ex maps message["$type"] to event.event_type.
    # But message["$type"] is "#commit". 
    # The COLLECTION is what tells us if it's a post.
    
    collection = Map.get(event, :collection) || Map.get(event, "collection")
    
    # Optional debug sampling (1 in 1000) so we don't flood logs
    # if :rand.uniform(1000) == 1, do: Logger.debug("LinkDetector sample: #{collection}")

    urls =
      case collection do
        "app.bsky.feed.post" ->
          links = extract_links(event)
          
          # Cache for reposts
          # Jetstream gives us 'cid' at top level
          cid = Map.get(event, :cid) || Map.get(event, "cid")
          if cid && links != [] do
             :ets.insert(@ets_table, {cid, links})
          end
          
          links

        "app.bsky.feed.repost" ->
          # Repost logic requires parsing the record subject
          # Record is already a map in Jetstream!
          record = Map.get(event, :record) || Map.get(event, "record") || %{}
          subject = Map.get(record, "subject") || %{}
          orig_cid = Map.get(subject, "cid")
          
          if orig_cid do
            case :ets.lookup(@ets_table, orig_cid) do
              [{^orig_cid, links}] -> links
              [] -> [] 
            end
          else
            []
          end
          
        _ -> []
      end

    if urls != [] do
      # Logger.info("🔗 Found links: #{inspect(urls)}")
      payload = %{event_id: Map.get(event, :seq), urls: urls, raw: event}
      Phoenix.PubSub.broadcast(Skywire.PubSub, "link_events", {:link_event, payload})
    end
  end

  defp extract_links(event) do
    # Try to find facets in the record
    record = Map.get(event, :record) || Map.get(event, "record") || %{}
    facets = Map.get(record, "facets") || Map.get(record, :facets)
    
    do_extract_links(facets)
  end

  defp do_extract_links(facets) when is_list(facets) do
    facets
    |> Enum.flat_map(fn facet ->
      features = Map.get(facet, "features") || Map.get(facet, :features) || []
      Enum.map(features, fn feature ->
        type = Map.get(feature, "$type")
        # Match both standard Lexicon ID forms
        if type in ["app.bsky.richtext.facet.link", "app.bsky.richtext.facet#link"] do
           Map.get(feature, "uri")
        else
           nil
        end
      end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp do_extract_links(_), do: []
end
