defmodule Skywire.Search.OpenSearch do
  @moduledoc """
  Client for interacting with OpenSearch.
  Handles index creation and bulk ingestion.
  """
  require Logger

  @index_name "firehose_events"
  @dimensions 384 # MiniLM-L6-v2

  defp base_url do
    System.get_env("OPENSEARCH_URL") || "http://localhost:9200"
  end

  @doc """
  Create the index with k-NN vector mapping if it doesn't exist.
  """
  def setup do
    url = "#{base_url()}/#{@index_name}"
    
    mapping = %{
      settings: %{
        "index.knn" => true,
        "number_of_shards" => 1,
        "number_of_replicas" => 0
      },
      mappings: %{
        properties: %{
          embedding: %{
            type: "knn_vector",
            dimension: @dimensions,
            method: %{
              name: "hnsw",
              engine: "nmslib",
              space_type: "l2"
            }
          },
          text: %{type: "text"}, # Standard Lucene analyzer
          uri: %{type: "keyword"},
          author: %{type: "keyword"}, # Exact match for DIDs
          indexed_at: %{type: "date"},
          # Store the full raw record as a non-indexed object if we want, 
          # but usually flattened fields are better. Let's store raw as object with dynamic: false
          raw_record: %{
            type: "object", 
            dynamic: false 
          }
        }
      }
    }

    # Check existence
    case Req.head!(url).status do
      200 -> 
        Logger.info("OpenSearch index '#{@index_name}' already exists.")
        :ok
      404 ->
        Logger.info("Creating OpenSearch index '#{@index_name}'...")
        case Req.put(url, json: mapping) do
          {:ok, %{status: 200}} -> :ok
          {:error, reason} -> {:error, reason}
          resp -> {:error, resp}
        end
    end
  end

  @doc """
  Bulk index a list of tuples: `{event, embedding}`.
  """
  def bulk_index(events_with_embeddings) do
    # Convert to NDJSON for _bulk API
    # Line 1: Action/Metadata
    # Line 2: Document
    
    body = 
      events_with_embeddings
      |> Enum.map(fn {event, embedding} ->
        id = event.record["uri"] || "at://#{event.repo}/#{event.collection}/#{event.record["rkey"]}"
        
        meta = %{
          index: %{
            _index: @index_name,
            _id: id
          }
        }
        
        doc = %{
          uri: id,
          text: event.record["text"],
          author: event.repo,
          indexed_at: event.indexed_at,
          raw_record: event.record,
          embedding: embedding
        }

        [Jason.encode!(meta), Jason.encode!(doc)]
      end)
      |> List.flatten()
      |> Enum.join("\n")
      
    # _bulk expects a final newline
    body = body <> "\n"

    Req.post("#{base_url()}/_bulk", 
      body: body, 
      headers: [{"content-type", "application/x-ndjson"}]
    )
  end
end
