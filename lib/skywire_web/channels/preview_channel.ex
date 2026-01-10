defmodule SkywireWeb.PreviewChannel do
  use SkywireWeb, :channel
  alias Skywire.ML.Embedding
  require Logger

  @common_pubsub_topic "firehose"

  @doc """
  Join the channel.
  Params:
    - "query": The search text to preview.
    - "threshold": The similarity threshold (0.0 to 1.0).
  """
  def join("preview", %{"query" => query, "threshold" => threshold}, socket) do
    # Generate embedding for the query immediately
    case Embedding.generate(query, :api) do
      nil ->
        {:error, %{reason: "failed_to_generate_embedding"}}
        
      query_embedding ->
        # Subscribe to the global firehose feed
        Phoenix.PubSub.subscribe(Skywire.PubSub, @common_pubsub_topic)
        
        # Store query settings in socket state for fast filtering
        socket = assign(socket, :query_vec, query_embedding)
        socket = assign(socket, :threshold, threshold)
        
        {:ok, socket}
    end
  end

  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{ping: "pong"}}, socket}
  end

  # Receive broadcast from Firehose Processor
  def handle_info({:new_embeddings, events_with_embeddings}, socket) do
    query_vec = socket.assigns.query_vec
    threshold = socket.assigns.threshold

    # Filter the batch for matches against THIS socket's query
    matches = Enum.reduce(events_with_embeddings, [], fn {event, embedding}, acc ->
      score = calculate_similarity(query_vec, embedding)
      
      if score >= threshold do
        payload = %{
          post: %{
            uri: event.record["uri"] || "at://#{event.repo}/#{event.collection}/#{event.record["rkey"]}",
            text: event.record["text"],
            author: event.repo,
            indexed_at: event.indexed_at,
            raw_record: event.record
          },
          score: score
        }
        [payload | acc]
      else
        acc
      end
    end)

    # Push matches to client (if any)
    if length(matches) > 0 do
      push(socket, "new_match", %{matches: matches})
    end

    {:noreply, socket}
  end
  
  # Copy-paste of robust similarity from Matcher
  defp calculate_similarity(vec1, vec2) do
    l1 = if is_struct(vec1, Pgvector), do: Pgvector.to_list(vec1), else: vec1
    l2 = if is_struct(vec2, Pgvector), do: Pgvector.to_list(vec2), else: vec2

    dot = 
      Enum.zip(l1, l2)
      |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
      
    mag1 = :math.sqrt(Enum.reduce(l1, 0.0, fn x, acc -> acc + x*x end))
    mag2 = :math.sqrt(Enum.reduce(l2, 0.0, fn x, acc -> acc + x*x end))
    
    if mag1 == 0 or mag2 == 0 do
      0.0
    else
      dot / (mag1 * mag2)
    end
  end
end
