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
    Logger.debug("Received frame: #{byte_size(data)} bytes")
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
    case CBOR.decode(data) do
      # Frame with body (Header + Body)
      {:ok, header, rest} when byte_size(rest) > 0 ->
        process_frame_header(header, rest)
        
      # Frame without body (Header only)
      {:ok, header, _empty} ->
        process_frame_header(header, nil)
        
      {:ok, header} ->
        process_frame_header(header, nil)

      {:error, reason} ->
        {:error, reason}
        
      other ->
        {:error, {:unexpected_return, other}}
    end
  end

  defp process_frame_header(%{"op" => 1, "t" => "#commit"}, body_binary) when is_binary(body_binary) do
    # Commit event: Body contains the actual data
    case CBOR.decode(body_binary) do
      {:ok, body, _} -> extract_and_process_event(body)
      {:ok, body} -> extract_and_process_event(body)
      error -> error
    end
  end

  defp process_frame_header(%{"op" => 1}, _), do: :ok # Missing body?
  
  defp process_frame_header(%{"op" => -1}, _rest) do
    # Error frame
    Logger.warning("Received error frame from firehose")
    :ok
  end
  
  defp process_frame_header(header, _rest) do
    Logger.debug("Skipping frame type: #{inspect(header)}")
    :ok
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

  defp extract_and_process_event(message) do
    # Skip messages without seq (e.g., info messages)
    Logger.warning("Unknown message format: #{inspect(message, limit: :infinity)}")
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
      "ops" => sanitize(ops),
      "repo" => Map.get(message, "repo"),
      "time" => Map.get(message, "time")
    }
  end

  defp extract_record(message), do: sanitize(message)

  defp sanitize(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {sanitize(k), sanitize(v)} end)
  end

  defp sanitize(list) when is_list(list) do
    Enum.map(list, &sanitize/1)
  end

  # Handle CBOR Tags (CIDs are tag 42)
  defp sanitize(%CBOR.Tag{tag: 42, value: %CBOR.Tag{tag: :bytes, value: bytes}}) do
    "CID(#{Base.encode16(bytes, case: :lower)})"
  end

  defp sanitize(%CBOR.Tag{tag: 42, value: value}) when is_binary(value) do
    "CID(#{Base.encode16(value, case: :lower)})"
  end

  defp sanitize(%CBOR.Tag{tag: :bytes, value: bytes}) do
    sanitize(bytes)
  end

  defp sanitize(%CBOR.Tag{value: value, tag: tag}) do
    %{"$tag" => tag, "value" => sanitize(value)}
  end

  defp sanitize(binary) when is_binary(binary) do
    if String.valid?(binary) do
      binary
    else
      # Encode non-UTF8 binaries as base64 with prefix
      "base64:#{Base.encode64(binary)}"
    end
  end

  defp sanitize(other), do: other
end

