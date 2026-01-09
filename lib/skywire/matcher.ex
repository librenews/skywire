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
    # TODO: Optimize this. Currently we do 1 query per post.
    # With 32 posts/batch, that's 32 queries/batch. Fine for now.
    matches = Subscriptions.find_matches(embedding)
    
    Enum.each(matches, fn sub ->
      score = calculate_similarity(sub.embedding, embedding)
      if score >= sub.threshold do
        dispatch_webhook(sub, event, score)
      end
    end)
  end
  
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
        indexed_at: event.indexed_at
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
