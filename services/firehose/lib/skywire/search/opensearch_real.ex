defmodule Skywire.Search.OpenSearch.Real do
  @moduledoc """
  Client for interacting with OpenSearch.
  Handles index creation and bulk ingestion.
  """
  require Logger

  @index_name "firehose_events"
  @dimensions 384 # bge-small-en-v1.5

  defp base_url do
    System.get_env("OPENSEARCH_URL") || "http://localhost:9200"
  end




  @percolator_index "skywire_subs"

  @doc """
  Checks if OpenSearch is up and reachable.
  """
  def health_check do
    case Req.get("#{base_url()}/_cluster/health", receive_timeout: 2000) do
      {:ok, %{status: 200}} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  @doc """
  Setup indices for both Data (firehose) and Queries (percolator).
  """
  def setup do
    setup_data_index()
    setup_percolator_index()
  end

  defp setup_data_index do
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
          text: %{type: "text"}, 
          uri: %{type: "keyword"},
          author: %{type: "keyword"}, # Exact match for DIDs
          indexed_at: %{type: "date"},
          raw_record: %{
            type: "object", 
            dynamic: false 
          }
        }
      }
    }

    create_if_missing(url, mapping, @index_name)
  end

  defp setup_percolator_index do
    url = "#{base_url()}/#{@percolator_index}"

    mapping = %{
      mappings: %{
        properties: %{
          # The query itself
          query: %{
            type: "percolator"
          },
          # Fields we can filter on (metadata about the sub)
          threshold: %{ type: "float" },
          external_id: %{ type: "keyword" },
          callback_url: %{ type: "keyword" },
          
          # Fields that the percolator query can target (must match Data Index)
          text: %{type: "text"}, 
          uri: %{type: "keyword"},
          author: %{type: "keyword"}, # Exact match for DIDs
          indexed_at: %{type: "date"},
          raw_record: %{
            type: "object", 
            dynamic: false 
          }
        }
      }
    }
    
    create_if_missing(url, mapping, @percolator_index)
  end

  defp create_if_missing(url, mapping, name) do
    case Req.head!(url).status do
      200 -> 
        Logger.info("OpenSearch index '#{name}' already exists.")
        :ok
      404 ->
        Logger.info("Creating OpenSearch index '#{name}'...")
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
          raw_record: event.record
        }
        
        # Only add embedding if present (Keyword-Only Mode support)
        doc = if embedding, do: Map.put(doc, :embedding, embedding), else: doc

        [Jason.encode!(meta), Jason.encode!(doc)]
      end)
      |> List.flatten()
      |> Enum.join("\n")
      
    # _bulk expects a final newline
    body = body <> "\n"

    case Req.post("#{base_url()}/_bulk", 
      body: body, 
      headers: [{"content-type", "application/x-ndjson"}],
      receive_timeout: 60_000
    ) do
      {:ok, %{status: 200} = resp} -> {:ok, resp}
      {:ok, %{status: 429, body: body}} -> 
        Logger.error("OpenSearch Circuit Breaker (429) during Bulk Index: #{inspect(body["error"]["reason"])}")
        {:error, :circuit_breaker}
      {:ok, %{status: status, body: body}} -> {:error, "Status #{status}: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Percolate a batch of documents against the registered subscriptions.
  Returns list of matches.
  """
  def percolate_batch(events_with_embeddings) do
    # Multi-Percolate Header (target index)
    header = Jason.encode!(%{index: @percolator_index})
    
    body = 
      events_with_embeddings
      |> Enum.map(fn {event, embedding} ->
        # The document to match against
        doc = %{
          embedding: embedding,
          text: event.record["text"],
          author: event.repo
        }
        
        # We need the doc itself in the query part
        query_part = %{
           query: %{
             percolate: %{
               field: "query",
               document: doc
             }
           }
        }
        
        # Msearch/Mpercolate format: Header \n Query \n
        [header, Jason.encode!(query_part)]
      end)
      |> List.flatten()
      |> Enum.join("\n")
      
    body = body <> "\n"

    # NOTE: We query the SUBSCRIPTION index (@percolator_index) using the msearch endpoint
    # wait... mpercolate isn't a standard endpoint in OS 2.x, it uses _msearch.
    # But wait, Percolate query creates a match.
    # Actually, proper way is standard _msearch against the PERCOLATOR index.
    
    # Log the body for debugging
    Logger.info("🔍 Percolate Request Body: #{String.slice(body, 0, 500)}...")

    url = "#{base_url()}/#{@percolator_index}/_msearch"
    
    case Req.post(url, body: body, headers: [{"content-type", "application/x-ndjson"}], receive_timeout: 60_000) do
      {:ok, %{status: 200, body: %{"responses" => responses}}} ->
        # Correlate responses with events
        Enum.zip(events_with_embeddings, responses)
        |> Enum.map(fn {{event, _emb}, resp} ->
           hits = resp["hits"]["hits"] || []
           {event, hits}
        end)
      
      {:ok, %{status: 429, body: body}} ->
        Logger.warning("OpenSearch Circuit Breaker (429): #{inspect(body["error"]["reason"])}")
        []

      {:ok, %{status: status, body: body}} ->
        Logger.error("Percolate failed with status #{status}: #{inspect(body)}")
        []

      {:error, reason} -> 
        Logger.error("Percolate error: #{inspect(reason)}")
        []
    end
  end

  def index_subscription(id, doc) do
    url = "#{base_url()}/#{@percolator_index}/_doc/#{id}"
    res = Req.put(url, json: doc)
    IO.inspect(res, label: "OS PUT Response")
    res
  end

  def delete_subscription(id) do
    url = "#{base_url()}/#{@percolator_index}/_doc/#{id}"
    Req.delete(url)
  end

  def get_subscription(id) do
    url = "#{base_url()}/#{@percolator_index}/_doc/#{id}"
    case Req.get(url) do
      {:ok, %{status: 200, body: %{"_source" => source}}} -> {:ok, source}
      _ -> {:error, :not_found}
    end
  end
end
