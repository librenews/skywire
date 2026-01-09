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

  def embedding_stats do
    total = Repo.aggregate(Event, :count, :seq)
    
    with_embedding = from(e in Event, where: not is_nil(e.embedding)) 
                     |> Repo.aggregate(:count, :seq)
                     
    %{
      total_events: total,
      with_embeddings: with_embedding,
      coverage: (if total > 0, do: Float.round(with_embedding / total * 100, 2), else: 0.0)
    }
  end
end
