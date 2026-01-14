defmodule Skywire.Firehose.Connection do
  @moduledoc """
  WebSocket client for the Bluesky firehose.
  
  Connects to wss://bsky.network/xrpc/com.atproto.sync.subscribeRepos
  and processes incoming CBOR-encoded events.
  
  On disconnect or error, this process crashes and the supervisor restarts it,
  providing exponential backoff and clean state reset.
  """
  use WebSockex
  require Logger
  alias Skywire.Firehose.{CursorStore, Processor}

  # Jetstream URL (e.g., us-east instance)
  # requesting only posts and reposts to save bandwidth
  @jetstream_url "wss://jetstream2.us-east.bsky.network/subscribe?wantedCollections=app.bsky.feed.post&wantedCollections=app.bsky.feed.repost"

  def start_link(opts) do
    # Jetstream uses time_us as cursor usually, but we can just start live or resume if we stored it.
    # For now, let's just start live to simplify, or append cursor if we have one.
    # Jetstream cursor param is `?cursor=...` (unix microsecond timestamp)
    
    cursor = CursorStore.get_cursor()
    # Support for partitioned streams
    partition_index = System.get_env("JETSTREAM_PARTITION")
    partition_count = System.get_env("JETSTREAM_PARTIES")
    
    url = build_url(cursor, partition_index, partition_count)
    
    Logger.info("Connecting to Bluesky Jetstream: #{url}")
    
    # Ping interval to keep connection alive
    WebSockex.start_link(url, __MODULE__, %{}, opts)
  end

  # Jetstream sends JSON text frames
  @impl true
  def handle_frame({:text, data}, state) do
    case Jason.decode(data) do
      {:ok, %{"kind" => "commit"} = msg} ->
        process_commit(msg)
        {:ok, state}
        
      {:ok, _other_msg} ->
        # Ignore account events, identity events, etc.
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to decode JSON: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_frame({:binary, _data}, state) do
    Logger.warning("Received unexpected binary frame")
    {:ok, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("Disconnected from Jetstream: #{inspect(reason)}")
    {:close, reason, state}
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("Connected to Jetstream")
    {:ok, state}
  end

  ## Private Functions

  defp build_url(cursor, index, count) when is_binary(index) and is_binary(count) do
    base = build_url(cursor)
    "#{base}&partitions=#{count}&partition=#{index}"
  end
  defp build_url(cursor, _, _), do: build_url(cursor)

  defp build_url(cursor) when is_integer(cursor) and cursor > 0 do
    "#{@jetstream_url}&cursor=#{cursor}"
  end
  defp build_url(_), do: @jetstream_url

  defp process_commit(%{"commit" => commit, "time_us" => time_us, "did" => repo}) do
    # Jetstream structure:
    # {
    #   "kind": "commit",
    #   "did": "did:plc:...",
    #   "time_us": 170...,
    #   "commit": {
    #     "collection": "app.bsky.feed.post",
    #     "record": { ... },
    #     "rkey": "...",
    #     "operation": "create",
    #     "cid": "..."
    #   }
    # }

    # We only care about creates (new posts)
    if commit["operation"] == "create" do
      event = %{
        # Use time_us as the distinct sequence/cursor
        seq: time_us, 
        repo: repo,
        # Jetstream uses 'collection' in the inner commit object
        collection: commit["collection"],
        # Jetstream provides the 'cid' explicitly
        cid: commit["cid"],
        # The record is PRE-DECODED JSON!
        record: commit["record"],
        # For compatibility with LinkDetector logic which looks at event_type
        event_type: "commit" 
      }
      
      Processor.process_event(event)
    end
  end
  
  defp process_commit(_), do: :ok
end

