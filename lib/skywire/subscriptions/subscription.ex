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
    field :callback_url, :string

    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:external_id, :query, :embedding, :threshold, :callback_url])
    |> validate_required([:external_id, :query, :callback_url])
    |> unique_constraint(:external_id)
  end
end
