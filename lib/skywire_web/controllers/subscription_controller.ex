defmodule SkywireWeb.SubscriptionController do
  use SkywireWeb, :controller

  alias Skywire.Subscriptions
  alias Skywire.ML.Embedding

  action_fallback SkywireWeb.FallbackController

  def create(conn, %{"external_id" => _eid, "query" => query} = params) do
    # 1. Generate embedding for the query
    # Using :api serving for low latency
    case Embedding.generate(query, :api) do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to generate embedding for query"})

      vector ->
        # 2. Merge vector into params
        attrs = Map.put(params, "embedding", vector)

        # 3. Create subscription
        with {:ok, subscription} <- Subscriptions.create_subscription(attrs) do
          conn
          |> put_status(:created)
          |> json(%{
            id: subscription.id,
            external_id: subscription.external_id,
            status: "active"
          })
        end
    end
  end

  def delete(conn, %{"id" => external_id}) do
    case Subscriptions.delete_subscription_by_external_id(external_id) do
      {:ok, _sub} ->
        send_resp(conn, :no_content, "")
      
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Subscription not found"})
    end
  end

  def update(conn, %{"id" => external_id} = params) do
    # Filter out "id" from params so we don't try to update it
    attrs = Map.delete(params, "id")

    case Subscriptions.update_subscription_by_external_id(external_id, attrs) do
      {:ok, subscription} ->
        json(conn, %{
          id: subscription.id,
          external_id: subscription.external_id,
          status: "updated",
          threshold: subscription.threshold
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Subscription not found"})
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid parameters", details: inspect(changeset.errors)})
    end
  end
end
