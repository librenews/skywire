defmodule Skywire.Matcher do
  @moduledoc """
  Processes new events and matches them against active subscriptions.
  """
  use GenServer
  require Logger
  alias Skywire.Subscriptions

  # Simple in-memory buffer to batch matching if needed, 
  # or can just process directly. For thousands of subs, direct DB query per batch of posts is fine.
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Logger.info("Matcher started")
    {:ok, %{}}
  end

  @doc """
  Async match and notify.
  Called by Firehose.Processor.
  """
  def check_matches(events_with_embeddings) do
    # We spawn a Task so we don't block the firehose ingestion.
    # In a real heavy system, this would go into a queue (Oban).
    Task.start(fn -> 
      Enum.each(events_with_embeddings, &process_event/1)
    end)
  end

  defp process_event({event, embedding}) do
    # Find matching subscriptions
    # Note: find_matches currently sorts by distance to the embedding.
    # If the subscription has NO embedding (keyword only), it might not show up if find_matches uses the vector index strictly.
    # We need to ensure we fetch ALL subscriptions or handle keyword-only subs differently.
    # For now, assuming find_matches returns relevant subs or we fetch all active subs if the dataset is small.
    # Given the previous context, find_matches executes: from(s in Subscription, order_by: l2_distance(...)) |> Repo.all()
    # This might crash if s.embedding is nil.
    # For this iteration, let's assume we are still iterating candidates.
    
    matches = Subscriptions.find_matches(embedding)
    
    Enum.each(matches, fn sub ->
      score = if sub.embedding, do: calculate_similarity(sub.embedding, embedding), else: 0.0
      
      # Hybrid Filter: Similarity OR Keywords
      # If keyword match, we treat it as a perfect match (Score 1.0) or matched by keyword.
      kw_match = keyword_match?(sub.keywords, event.record["text"])
      
      if (sub.embedding && score >= sub.threshold) or kw_match do
        final_score = if kw_match, do: 1.0, else: score
        dispatch_webhook(sub, event, final_score)
      end
    end)
  end

  defp keyword_match?(nil, _text), do: false
  defp keyword_match?([], _text), do: false
  defp keyword_match?(_keywords, nil), do: false
  defp keyword_match?(keywords, text) do
    downcase_text = String.downcase(text)
    Enum.any?(keywords, fn kw -> 
      String.contains?(downcase_text, String.downcase(kw))
    end)
  end
  
  defp calculate_similarity(nil, _vec2), do: 0.0
  defp calculate_similarity(_vec1, nil), do: 0.0
  defp calculate_similarity(vec1, vec2) do
    # Unwrap Pgvector struct if present
    l1 = if is_struct(vec1, Pgvector), do: Pgvector.to_list(vec1), else: vec1
    l2 = if is_struct(vec2, Pgvector), do: Pgvector.to_list(vec2), else: vec2

    # Dot Product
    dot = 
      Enum.zip(l1, l2)
      |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
      
    # Magnitudes (Norms)
    mag1 = :math.sqrt(Enum.reduce(l1, 0.0, fn x, acc -> acc + x*x end))
    mag2 = :math.sqrt(Enum.reduce(l2, 0.0, fn x, acc -> acc + x*x end))
    
    # Cosine Similarity = Dot / (Mag1 * Mag2)
    if mag1 == 0 or mag2 == 0 do
      0.0
    else
      dot / (mag1 * mag2)
    end
  end

  defp dispatch_webhook(sub, event, score) do
    payload = %{
      subscription_id: sub.external_id,
      match_score: score,
      post: %{
        uri: event.record["uri"] || "at://#{event.repo}/#{event.collection}/#{event.record["rkey"]}", # Construct URI if creating form record
        text: event.record["text"],
        author: event.repo,
        indexed_at: event.indexed_at,
        raw_record: event.record
      }
    }
    
    Logger.info("🪝 Dispatching webhook for subscription #{sub.external_id} (Score: #{score})")
    
    # Fire and forget HTTP request
    Task.start(fn -> 
      case Req.post(sub.callback_url, json: payload, retry: :safe_transient, max_retries: 3) do
        {:ok, %{status: 200}} -> :ok
        {:ok, %{status: status}} -> Logger.warning("Webhook failed with status #{status}")
        {:error, reason} -> Logger.error("Webhook failed: #{inspect(reason)}")
      end
    end)
  end
end
