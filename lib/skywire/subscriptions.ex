defmodule Skywire.Subscriptions do
  @moduledoc """
  The Subscriptions context.
  """

  alias Skywire.Subscriptions.Subscription

  alias Skywire.Search.OpenSearch
  alias Skywire.Auth.Validator # We will need a validator for changesets if we drop Ecto schema validation

  # We can still use the Ecto Schema for changeset validation, but we won't insert into Repo.
  
  def create_subscription(attrs \\ %{}) do
    changeset = Subscription.changeset(%Subscription{}, attrs)
    
    if changeset.valid? do
      sub = Ecto.Changeset.apply_changes(changeset)
      
      # Build OpenSearch Query Document
      query_doc = build_percolator_query(sub)
      
      # Index into OpenSearch (using external_id as _id)
      # We need a helper for indexing a single doc to the percolator index
      OpenSearch.index_subscription(sub.external_id, query_doc)
      
      {:ok, sub}
    else
      {:error, changeset}
    end
  end

  def delete_subscription_by_external_id(external_id) do
    OpenSearch.delete_subscription(external_id)
  end
  
  def get_subscription_by_external_id(external_id) do
    # Fetch from OpenSearch via GET
    case OpenSearch.get_subscription(external_id) do
      {:ok, doc} -> 
        # Map back to struct
        %Subscription{
           external_id: doc["external_id"],
           # callback_url is deprecated
           threshold: doc["threshold"],
           # Reconstructing the full struct might be hard if we don't store everything perfectly
           # But mainly we just need existence check here.
        }
      _ -> nil
    end
  end

  def update_subscription_by_external_id(external_id, attrs) do
     # Fetch, Merge, Save
     # Simplified for now: just overwrite
     create_subscription(Map.put(attrs, "external_id", external_id))
  end

  defp build_percolator_query(sub) do
    # Logic: (Vector Similarity > Threshold) OR (Keyword Match)
    
    # 1. Vector Part (Script Query)
    vector_query = 
      if sub.embedding do
        %{
          "script" => %{
            "script" => %{
              "source" => "knn_score(doc['embedding'], params.query_value) >= params.threshold",
              "lang" => "knn",
              "params" => %{
                "query_value" => sub.embedding,
                "threshold" => sub.threshold
              }
            }
          }
        }
      else
        nil
      end

    # 2. Keyword Part (Text Match)
    keyword_query = 
      if sub.keywords && sub.keywords != [] do
        %{
          "bool" => %{
             "should" => Enum.map(sub.keywords, fn kw -> 
                %{ "match_phrase" => %{ "text" => kw } }
             end),
             "minimum_should_match" => 1
          }
        }
      else
        nil
      end

    # Combine
    final_query = 
      case {vector_query, keyword_query} do
        {nil, nil} -> %{ "match_all" => %{} } # Catch all? Or match nothing?
        {v, nil} -> v
        {nil, k} -> k
        {v, k} -> 
          %{
            "bool" => %{
              "should" => [v, k],
              "minimum_should_match" => 1
            }
          }
      end

    %{
      "query" => final_query,
      "external_id" => sub.external_id,
      "threshold" => sub.threshold
    }
  end
