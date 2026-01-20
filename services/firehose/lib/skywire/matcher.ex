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
      Logger.info("👉 Matcher Task started")
      # 1. Ask OpenSearch: "Which subscriptions match these events?" 
      # 1. Ask OpenSearch: "Which subscriptions match these events?"
      results = OpenSearch.percolate_batch(events_with_embeddings)
      
      match_count = Enum.reduce(results, 0, fn {_event, hits}, acc -> acc + length(hits) end)
      if match_count > 0 do
        Logger.info("🔍 Percolator found #{match_count} matches in batch of #{length(events_with_embeddings)} events")
      else
         Logger.info("🔍 Percolator found 0 matches in batch of #{length(events_with_embeddings)} events")
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
