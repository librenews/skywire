defmodule Skywire.Debug do
  @moduledoc """
  Helper functions for debugging and verifying system state.
  """
  import Ecto.Query
  alias Skywire.Repo
  alias Skywire.Firehose.Event

  def link_stats(minutes \\ 5) do
    cutoff = DateTime.utc_now() |> DateTime.add(-minutes * 60, :second)
    
    total_query = from e in Event, where: e.indexed_at > ^cutoff
    total_count = Repo.aggregate(total_query, :count, :seq)
    
    # Count events where the 'facets' field in the record JSONB is present and not empty
    links_query = from e in Event,
      where: e.indexed_at > ^cutoff,
      where: fragment("?->'facets' IS NOT NULL AND jsonb_array_length(?->'facets') > 0", e.record, e.record)
      
    links_count = Repo.aggregate(links_query, :count, :seq)
    
    ratio = if total_count > 0, do: Float.round(links_count / total_count * 100, 2), else: 0.0
    
    IO.puts """
    
    === Skywire Firehose Stats (Last #{minutes} mins) ===
    Total Events:      #{total_count}
    Events w/ Links:   #{links_count}
    Link Ratio:        #{ratio}%
    ===============================================
    """
    
    %{total: total_count, with_links: links_count, ratio: ratio}
  end
  
  def recent_link_events(limit \\ 5) do
    query = from e in Event,
      where: fragment("?->'facets' IS NOT NULL AND jsonb_array_length(?->'facets') > 0", e.record, e.record),
      order_by: [desc: e.seq],
      limit: ^limit
      
    Repo.all(query)
  end

  def check_recent_embeddings(limit \\ 100) do
    # Ensure app is started
    Application.ensure_all_started(:skywire)
    
    # Just grab the last N events and check them
    query = from e in Event,
      order_by: [desc: e.seq],
      limit: ^limit,
      select: {e.seq, not is_nil(e.embedding)}
      
    results = Repo.all(query, timeout: 15_000)
    
    total_checked = length(results)
    with_embeds = Enum.count(results, fn {_, has_embed} -> has_embed end)
    
    %{
      checked_last_n: total_checked,
      found_with_embedding: with_embeds,
      # Return the sequence number of the latest post so we know it's fresh
      latest_seq: List.first(results) |> elem(0),
      status: if(with_embeds > 0, do: :working, else: :waiting_for_data)
    }
  end
  def check_vector_magnitude do
    vec = 
      case Skywire.ML.Cloudflare.generate_batch(["test string"]) do
        [emb] when is_list(emb) -> emb
        _ -> nil
      end
    
    if vec do
      sum_sq = Enum.reduce(vec, 0, fn x, acc -> acc + x*x end)
      magnitude = :math.sqrt(sum_sq)
      
      %{
         status: :ok,
         vector_length: length(vec),
         magnitude: magnitude,
         normalized?: abs(magnitude - 1.0) < 0.01
      }
    else
      %{status: :error, reason: "Model returned nil"}
    end
  end
end
