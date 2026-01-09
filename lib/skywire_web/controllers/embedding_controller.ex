defmodule SkywireWeb.EmbeddingController do
  use SkywireWeb, :controller
  import Ecto.Query
  import Pgvector.Ecto.Query
  alias Skywire.{Repo, Firehose.Event, ML.Embedding}

  def generate(conn, %{"text" => text}) do
    # Generate embedding using our serving process
    case Embedding.generate(text) do
      nil -> 
        conn |> put_status(400) |> json(%{error: "Failed to generate embedding"})
      vector ->
        json(conn, %{embedding: vector})
    end
  end

  def search(conn, %{"query" => query} = params) do
    limit = Map.get(params, "limit", 10)
    limit = if is_binary(limit), do: String.to_integer(limit), else: limit
    
    # 1. Generate embedding for query string
    case Embedding.generate(query) do
      nil ->
        conn |> put_status(400) |> json(%{error: "Failed to generate query embedding"})
      
      vector ->
        # 2. Search DB using Pgvector L2 distance (or cosine distance if normalized)
        embedding = Pgvector.new(vector)
        
        results = 
          from(e in Event,
            # Ensure we only search posts
            where: e.collection == "app.bsky.feed.post",
            # L2 distance is standard for unnormalized vectors, but cosine distance (<=>) is better for semantic similarity
            # Bumblebee/MiniLM often produce normalized vectors, let's stick to L2 or Cosine.
            # L2 (<->) is good. Cosine is (<=>).
            # Indices usually support L2. We created index with vector_l2_ops.
            order_by: l2_distance(e.embedding, ^embedding),
            limit: ^limit,
            select: map(e, [:seq, :repo, :record, :indexed_at, :collection])
          )
          |> Repo.all()
          
        json(conn, %{results: results})
    end
  end
end
