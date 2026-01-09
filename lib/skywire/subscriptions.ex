defmodule Skywire.Subscriptions do
  @moduledoc """
  The Subscriptions context.
  """

  import Ecto.Query, warn: false
  alias Skywire.Repo
  alias Skywire.Subscriptions.Subscription

  def list_subscriptions do
    Repo.all(Subscription)
  end

  def get_subscription_by_external_id(external_id) do
    Repo.get_by(Subscription, external_id: external_id)
  end

  def create_subscription(attrs \\ %{}) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  def delete_subscription(%Subscription{} = subscription) do
    Repo.delete(subscription)
  end
  
  def delete_subscription_by_external_id(external_id) do
    case get_subscription_by_external_id(external_id) do
      nil -> {:error, :not_found}
      sub -> Repo.delete(sub)
    end
  end

  @doc """
  Finds subscriptions that match the given embedding vector.
  Uses cosine distance (<=>) or L2 (<->). Using L2 as per index.
  """
  def find_matches(embedding_vector, limit \\ 100) do
    # Find subscriptions where the distance is small enough.
    # Note: threshold is usually "similarity" (0.8), but pgvector uses "distance".
    # Cosine Distance = 1 - Cosine Similarity.
    # So if threshold is 0.8 (high similarity), we want distance < 0.2.
    
    # However, we are using L2 distance in the index.
    # For normalized vectors, L2 distance is related to cosine distance.
    # L2^2 = 2 * (1 - CosineSimilarity).
    # This is getting complicated. Let's stick to Cosine Distance (<=>) in query
    # since that effectively maps to similarity.
    
    # We will fetch all subscriptions and filter in memory if the list is small,
    # OR we can do it in DB if we trust the index.
    # Let's query using the operator.
    
    from(s in Subscription,
      order_by: l2_distance(s.embedding, ^embedding_vector)
    )
    |> Repo.all()
    # We will refine the matching logic in the Matcher process to precise thresholding.
  end
end
