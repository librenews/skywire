defmodule Skywire.Auth.Token do
  @moduledoc """
  Schema for API tokens.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :string
    field :scopes, {:array, :string}, default: []
    field :active, :boolean, default: true

    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :token_hash, :scopes, :active])
    |> validate_required([:name, :token_hash])
  end
end
