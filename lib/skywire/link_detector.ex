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
  def handle_cast({:dispatch, %{"$type" => type} = event}, state) when type in ["app.bsky.feed.post", "app.bsky.feed.repost"] do
    Logger.info("LinkDetector received event: #{type}")
    urls =
      case type do
        "app.bsky.feed.post" ->
          links = extract_links(event)
          # cache links for reposts using the event's CID (if present)
          if cid = Map.get(event, "cid") do
            :ets.insert(@ets_table, {cid, links})
          end
          links

        "app.bsky.feed.repost" ->
          # Repost payload contains original CID under record.subject.cid
          orig_cid = get_in(event, ["record", "subject", "cid"])
          case :ets.lookup(@ets_table, orig_cid) do
            [{^orig_cid, links}] -> links
            [] ->
              # Fallback DB lookup not implemented yet
              []
          end
      end

    if urls != [] do
      payload = %{event_id: event["seq"], urls: urls, raw: event}
      Phoenix.PubSub.broadcast(Skywire.PubSub, "link_events", {:link_event, payload})
    end

    {:noreply, state}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  # -----------------------------------------------------------------
  defp extract_links(%{"$type" => "app.bsky.feed.post", "facets" => facets}) when is_list(facets) do
    facets
    |> Enum.flat_map(fn %{"features" => features} ->
      features
      |> Enum.map(fn
        %{"$type" => "app.bsky.richtext.facet.link", "uri" => uri} -> uri
        _ -> nil
      end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_links(_), do: []
end
