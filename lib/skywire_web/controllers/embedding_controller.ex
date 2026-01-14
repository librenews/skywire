defmodule SkywireWeb.EmbeddingController do
  use SkywireWeb, :controller
  import Ecto.Query
  # import Pgvector.Ecto.Query # REMOVED: Dependency gone
  alias Skywire.{Repo, Firehose.Event, ML.Cloudflare}

  def generate(conn, %{"text" => text}) do
    # Generate embedding using Cloudflare API
    case Cloudflare.generate_batch([text]) do
      [vector] when is_list(vector) -> 
        json(conn, %{embedding: vector})
      _ -> 
        conn |> put_status(400) |> json(%{error: "Failed to generate embedding"})
    end
  end

  def search(conn, %{"query" => _query} = _params) do
    # Legacy SQL Search endpoint - Disabled in NoSQL Mode
    conn 
    |> put_status(501) 
    |> json(%{error: "Not Implemented. Use OpenSearch endpoint."})
  end
end
