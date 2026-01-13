defmodule Skywire.Subscriptions.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "subscriptions" do
    field :external_id, :string
    field :query, :string
    field :embedding, Pgvector.Ecto.Vector
    field :threshold, :float, default: 0.8
    # field :callback_url, :string # Deprecated
    field :keywords, {:array, :string}

    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:external_id, :query, :embedding, :threshold, :keywords])
    |> validate_required([:external_id])
    |> validate_query_or_keywords()
    |> unique_constraint(:external_id)
  end

  defp validate_query_or_keywords(changeset) do
    query = get_field(changeset, :query)
    keywords = get_field(changeset, :keywords)

    if (query == nil or query == "") and (keywords == nil or keywords == []) do
      add_error(changeset, :base, "Must provide either a semantic query or keywords")
    else
      changeset
    end
  end
end
