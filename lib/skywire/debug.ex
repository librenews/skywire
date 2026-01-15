defmodule Skywire.Debug do
  @moduledoc """
  Helper functions for debugging and verifying system state.
  """
  # import Ecto.Query
  # alias Skywire.Repo
  # alias Skywire.Firehose.Event

  def link_stats(_minutes \\ 5) do
    IO.puts "Debug.link_stats disabled (NoSQL migration)."
    %{total: 0, with_links: 0, ratio: 0.0}
  end
  
  def recent_link_events(_limit \\ 5) do
    IO.puts "Debug.recent_link_events disabled."
    []
  end

  def check_recent_embeddings(_limit \\ 100) do
    %{status: :disabled}
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
