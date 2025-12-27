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

  @firehose_url "wss://bsky.network/xrpc/com.atproto.sync.subscribeRepos"

  def start_link(opts) do
    cursor = CursorStore.get_cursor()
    url = build_url(cursor)
    
    Logger.info("Connecting to Bluesky firehose from cursor: #{cursor}")
    
    WebSockex.start_link(url, __MODULE__, %{}, opts)
  end

  @impl true
  def handle_frame({:binary, data}, state) do
    case decode_and_process(data) do
      :ok ->
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to process frame: #{inspect(reason)}")
        # Crash to trigger restart
        raise "Frame processing failed: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_frame({:text, _data}, state) do
    Logger.warning("Received unexpected text frame")
    {:ok, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("Disconnected from firehose: #{inspect(reason)}")
    # Let the process crash so supervisor can restart it
    {:close, reason, state}
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("Connected to Bluesky firehose")
    {:ok, state}
  end

  ## Private Functions

  defp build_url(cursor) when cursor > 0 do
    "#{@firehose_url}?cursor=#{cursor}"
  end

  defp build_url(_cursor) do
    @firehose_url
  end

  defp decode_and_process(data) do
    with {:ok, decoded} <- CBOR.decode(data),
         :ok <- extract_and_process_event(decoded) do
      :ok
    else
      error -> error
    end
  end

  defp extract_and_process_event(%{"seq" => seq} = message) do
    # Extract relevant fields from the firehose message
    event = %{
      seq: seq,
      repo: Map.get(message, "repo", ""),
      event_type: Map.get(message, "$type", "unknown"),
      collection: extract_collection(message),
      record: extract_record(message)
    }

    Processor.process_event(event)
    :ok
  end

  defp extract_and_process_event(_message) do
    # Skip messages without seq (e.g., info messages)
    :ok
  end

  defp extract_collection(%{"ops" => [%{"path" => path} | _]}) do
    # Extract collection from path like "app.bsky.feed.post/..."
    case String.split(path, "/") do
      [collection | _] -> collection
      _ -> nil
    end
  end

  defp extract_collection(_), do: nil

  defp extract_record(%{"blocks" => _blocks, "ops" => ops} = message) do
    # Store the full message as JSONB for now
    # Downstream consumers can decode CAR blocks if needed
    %{
      "ops" => ops,
      "repo" => Map.get(message, "repo"),
      "time" => Map.get(message, "time")
    }
  end

  defp extract_record(message), do: message
end
