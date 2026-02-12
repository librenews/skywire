defmodule SkywireWeb.PreviewChannel do
  use SkywireWeb, :channel
  require Logger

  @common_pubsub_topic "firehose"

  @doc """
  Join the channel.
  Params:
    - "query": The search text to preview.
    - "threshold": The similarity threshold (0.0 to 1.0).
  """
  def join("preview", payload, socket) do
    query = payload["query"]
    keywords = payload["keywords"]
    threshold = payload["threshold"] || 0.8 # Default threshold

    if (is_nil(query) or query == "") and (is_nil(keywords) or keywords == []) do
      {:error, %{reason: "must_provide_query_or_keywords"}}
    else
      # Generate embedding if query provided
      query_vec = 
        if query && query != "" do
          case Skywire.ML.generate_batch([query]) do
            [emb] when is_list(emb) -> emb
            _ -> nil
          end
        else
          nil
        end

      # Subscribe to the global firehose feed
      Phoenix.PubSub.subscribe(Skywire.PubSub, @common_pubsub_topic)
      
      # Store settings
      socket = 
        socket
        |> assign(:query_vec, query_vec)
        |> assign(:keywords, keywords || [])
        |> assign(:threshold, threshold)
      
      {:ok, socket}
    end
  end

  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{ping: "pong"}}, socket}
  end

  # Receive broadcast from Firehose Processor
  def handle_info({:new_embeddings, events_with_embeddings}, socket) do
    query_vec = socket.assigns.query_vec
    keywords = socket.assigns.keywords
    threshold = socket.assigns.threshold

    # Filter the batch for matches against THIS socket's settings
    matches = Enum.reduce(events_with_embeddings, [], fn {event, embedding}, acc ->
      
      # 1. Calculate Semantic Score (if we have a query vector)
      semantic_score = 
        if query_vec do
          calculate_similarity(query_vec, embedding)
        else
          0.0
        end

      # 2. Check Keyword Match (if we have keywords)
      kw_match = keyword_match?(keywords, event.record["text"])

      # 3. Hybrid OR Logic
      if (query_vec && semantic_score >= threshold) || kw_match do
        final_score = if kw_match, do: 1.0, else: semantic_score
        
        payload = %{
          post: %{
            uri: event.record["uri"] || "at://#{event.repo}/#{event.collection}/#{event.record["rkey"]}",
            text: event.record["text"],
            author: event.repo,
            indexed_at: event.indexed_at,
            raw_record: event.record
          },
          score: final_score
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

  defp keyword_match?(nil, _text), do: false
  defp keyword_match?([], _text), do: false
  defp keyword_match?(_keywords, nil), do: false
  defp keyword_match?(keywords, text) do
    # Use word boundaries for exact word matching (case-insensitive)
    Enum.any?(keywords, fn kw -> 
      # Escape special regex characters in the keyword
      escaped_kw = Regex.escape(kw)
      # Create regex with word boundaries for exact match
      pattern = ~r/\b#{escaped_kw}\b/i
      Regex.match?(pattern, text)
    end)
  end
  
  # Copy-paste of robust similarity from Matcher
  defp calculate_similarity(nil, _vec2), do: 0.0
  defp calculate_similarity(_vec1, nil), do: 0.0
  defp calculate_similarity(vec1, vec2) do
    l1 = vec1
    l2 = vec2

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
