defmodule Skywire.ML do
  @moduledoc """
  Behaviour and Proxy for Machine Learning Services (Embeddings).
  """

  @callback generate_batch(list(String.t()), String.t() | nil) :: list(list(float())) | nil

  def generate_batch(texts, model \\ nil) do
    impl().generate_batch(texts, model)
  end

  defp impl do
    Application.get_env(:skywire, :ml_impl, Skywire.ML.Local)
  end
end
