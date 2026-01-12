defmodule Skywire.Subscriptions do
  @moduledoc """
  The Subscriptions context.
  """

  import Ecto.Query, warn: false
  import Pgvector.Ecto.Query
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

  def update_subscription_by_external_id(external_id, attrs) do
    case get_subscription_by_external_id(external_id) do
      nil -> {:error, :not_found}
      sub -> 
        sub
        |> Subscription.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Finds subscriptions that match the given embedding vector.
  Uses cosine distance (<=>) or L2 (<->). Using L2 as per index.
  """
  def find_matches(embedding_vector, _limit \\ 100) do
    if is_nil(embedding_vector) do
      # No embedding (e.g. image post), return all subs to check for keyword matches
      Repo.all(Subscription)
    else
      # Fetch all and let Matcher sort/filter. 
      # Ideally we would limit, but for alerting we need Recall > Precision.
      from(s in Subscription,
        order_by: l2_distance(s.embedding, ^embedding_vector)
      )
      |> Repo.all()
    end
  end
end
