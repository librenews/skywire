defmodule Skywire.ML.Cloudflare do
  @moduledoc """
  Behaviour and Proxy for Cloudflare Embeddings.
  
  In Test: uses Mock.
  In Prod: uses Skywire.ML.Cloudflare.Real.
  """

  @callback generate_batch([String.t()]) :: [list(float())] | nil

  def generate_batch(texts) do
    impl().generate_batch(texts)
  end

  defp impl do
    Application.get_env(:skywire, :cloudflare_impl, Skywire.ML.Cloudflare.Real)
  end
end
