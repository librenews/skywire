defmodule SkywireWeb.SubscriptionController do
  use SkywireWeb, :controller

  alias Skywire.Subscriptions


  action_fallback SkywireWeb.FallbackController

  require Logger

  def create(conn, %{"external_id" => _eid} = params) do
    # Handle optional query
    query = params["query"]
    
    vector_result = 
      if query && query != "" do
        case Skywire.ML.Local.generate_batch([query]) do
          [emb] when is_list(emb) -> emb
          _ -> nil
        end
      else
        nil
      end

    # If query was provided but generation failed
    if query && query != "" && vector_result == nil do
         conn
         |> put_status(:bad_request)
         |> json(%{error: "Failed to generate embedding for query"})
    else
         attrs = 
           if vector_result do
             Map.put(params, "embedding", vector_result)
           else
             params
           end

         case Subscriptions.create_subscription(attrs) do
           {:ok, subscription} ->
             conn
             |> put_status(:created)
             |> json(%{
               id: subscription.id,
               external_id: subscription.external_id,
               status: "active"
             })
             
           {:error, changeset} ->
             Logger.error("Subscription creation failed: #{inspect(changeset.errors)}")
             conn
             |> put_status(:unprocessable_entity)
             |> json(%{error: "Invalid parameters", details: inspect(changeset.errors)})
         end
    end
  end

  def show(conn, %{"id" => external_id}) do
    case Subscriptions.get_subscription_by_external_id(external_id) do
      %Skywire.Subscriptions.Subscription{} = subscription ->
        json(conn, %{
          id: subscription.id, # Note: this is actually null if not stored in Postgres, but we don't care.
          external_id: subscription.external_id,
          threshold: subscription.threshold,
          status: "active"
        })
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Subscription not found"})
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
        Logger.error("Subscription update failed: #{inspect(changeset.errors)}")
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid parameters", details: inspect(changeset.errors)})
    end
  end
end
