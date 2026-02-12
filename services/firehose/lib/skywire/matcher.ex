defmodule Skywire.Matcher do
  @moduledoc """
  Processes new events and matches them against active subscriptions using OpenSearch Percolator.
  """
  use GenServer
  require Logger
  alias Skywire.Search.OpenSearch

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
    Logger.info("👉 Matcher.check_matches called with #{length(events_with_embeddings)} events")
    # We spawn a Task so we don't block the firehose ingestion.
    Task.start(fn -> 
      # Filter for posts only (ignore reposts, likes, etc if they ever get here, though ingestion might already filter some)
      # We specifically want to avoid reposts getting into the matcher as they lack text and shouldn't trigger keyword matches.
      post_events = Enum.filter(events_with_embeddings, fn {event, _emb} -> 
        event.collection == "app.bsky.feed.post" and not is_nil(event.record["text"])
      end)

      if length(post_events) > 0 do
        Logger.info("👉 Matcher Task processing #{length(post_events)} posts (filtered from #{length(events_with_embeddings)} events)")
        
        # 1. Ask OpenSearch: "Which subscriptions match these events?"
        results = OpenSearch.percolate_batch(post_events)
        
        match_count = Enum.reduce(results, 0, fn {_event, hits}, acc -> acc + length(hits) end)
        if match_count > 0 do
          Logger.info("🔍 Percolator found #{match_count} matches in batch of #{length(post_events)} posts")
        else
           Logger.info("🔍 Percolator found 0 matches in batch of #{length(post_events)} posts")
        end
        
        # 2. Iterate results and dispatch webhooks
        Enum.each(results, fn {event, hits} -> 
          Enum.each(hits, fn hit -> 
            sub_data = hit["_source"]
            score = hit["_score"] # This is the score from the percolator query (script or match)
            
            # Dispatch
            dispatch_webhook(sub_data, event, score)
          end)
        end)
      else
        Logger.info("👉 Matcher Task skipped batch: No valid posts found after filtering.")
      end
    end)
  end

  defp dispatch_webhook(sub_data, event, score) do
    # Prepare payload
    # specific structure for the stream
    payload = %{
      subscription_id: sub_data["external_id"],
      match_score: score,
      post: %{
        uri: event.record["uri"] || "at://#{event.repo}/#{event.collection}/#{event.record["rkey"]}",
        text: event.record["text"],
        author: event.repo,
        indexed_at: event.indexed_at,
        raw_record: event.record
      }
    }
    
    # JSON encode the data payload
    json_payload = Jason.encode!(payload)

    Logger.info("🌊 Streaming match for #{sub_data["external_id"]} (Score: #{score})")
    
    # XADD skywire:matches * data <json>
    # We use fire-and-forget logic here, but Redis is fast enough to do it synchronously usually.
    # To avoid blocking the task heavily, we can still use Task.start if we want, 
    # but Redix is pretty optimized. Let's keep it sync inside the Task for simplicity.
    
    case Skywire.Redis.command(["XADD", "skywire:matches", "*", "data", json_payload]) do
      {:ok, _id} -> :ok
      {:error, reason} -> Logger.error("Failed to push to Redis Stream: #{inspect(reason)}")
    end
  end
end
