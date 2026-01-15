defmodule Skywire.ML.Cloudflare do
  @moduledoc """
  Behaviour and Proxy for Cloudflare Embeddings.
  
  In Test: uses Mock.
  In Prod: uses Skywire.ML.Cloudflare.Real.
  """

  @callback generate_batch([String.t()], String.t()) :: [list(float())] | nil

  def generate_batch(texts, model \\ "@cf/baai/bge-large-en-v1.5") do
    impl().generate_batch(texts, model)
  end

  defp impl do
    Application.get_env(:skywire, :cloudflare_impl, Skywire.ML.Cloudflare.Real)
  end
end
