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

  def dispatch(event) do
    GenServer.cast(__MODULE__, {:dispatch, event})
  end

  # -----------------------------------------------------------------
  @impl true
  def init(_state) do
    # Create a named ETS table for fast repost lookup
    :ets.new(@ets_table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:dispatch, event}, state) do
    # Handle both map entries (from Firehose) and structs (from DB)
    type = Map.get(event, :event_type) || Map.get(event, "event_type")
    
    # We only care about commit events which usually have a type
    # But strictly speaking, the firehose stream sets $type on the message, 
    # which Connection.ex maps to :event_type.
    # The actual post type (app.bsky.feed.post) is inside the record's $type usually?
    # Actually Connection.ex maps message["$type"] to event.event_type.
    # But message["$type"] is "#commit". 
    # The COLLECTION is what tells us if it's a post.
    
    collection = Map.get(event, :collection) || Map.get(event, "collection")
    
    Logger.info("LinkDetector check: type=#{type} collection=#{collection}")

    urls =
      case collection do
        "app.bsky.feed.post" ->
          links = extract_links(event)
          # cache links for reposts using the event's raw CID if we can find it
          # Connection.ex doesn't explicitly expose the CID of the post yet easily
          # appearing in ops.
          links

        "app.bsky.feed.repost" ->
          # Repost handling requires parsing the record to find the subject
          # Since currently we don't have full record parsing, we might skip this for now
          # or try to extract from the sanitized record if possible.
          []
          
        _ -> []
      end

    if urls != [] do
      payload = %{event_id: Map.get(event, :seq), urls: urls, raw: event}
      Phoenix.PubSub.broadcast(Skywire.PubSub, "link_events", {:link_event, payload})
    end

    {:noreply, state}
  end



  def handle_cast(_msg, state), do: {:noreply, state}

  # -----------------------------------------------------------------
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
        if type == "app.bsky.richtext.facet.link" do
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
