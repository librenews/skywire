defmodule Skywire.Search.OpenSearch do
  @moduledoc """
  Behaviour and Proxy for OpenSearch Client.
  
  In Test: uses Mock.
  In Prod: uses Skywire.Search.OpenSearch.Real.
  """
  
  @callback health_check() :: :ok | :error
  @callback setup() :: :ok | {:error, any()}
  @callback bulk_index(list({map(), list(float()) | nil})) :: {:ok, map()} | {:error, any()}
  @callback percolate_batch(list({map(), list(float()) | nil})) :: list({map(), list(map())})
  @callback index_subscription(String.t(), map()) :: {:ok, map()} | {:error, any()}
  @callback delete_subscription(String.t()) :: {:ok, map()} | {:error, any()}
  @callback get_subscription(String.t()) :: {:ok, map()} | {:error, atom()}

  # Proxy Functions
  
  def health_check, do: impl().health_check()
  def setup, do: impl().setup()
  def bulk_index(events), do: impl().bulk_index(events)
  def percolate_batch(events), do: impl().percolate_batch(events)
  def index_subscription(id, doc), do: impl().index_subscription(id, doc)
  def delete_subscription(id), do: impl().delete_subscription(id)
  def get_subscription(id), do: impl().get_subscription(id)

  defp impl do
    Application.get_env(:skywire, :opensearch_impl, Skywire.Search.OpenSearch.Real)
  end
end
