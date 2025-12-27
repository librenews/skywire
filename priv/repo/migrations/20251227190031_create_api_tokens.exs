defmodule Skywire.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  def change do
    create table(:api_tokens) do
      add :name, :string, null: false
      add :token_hash, :string, null: false
      add :scopes, {:array, :string}, default: []
      add :active, :boolean, default: true

      timestamps()
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:active])
  end
end
