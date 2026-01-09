defmodule Skywire.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string, null: false
      add :query, :text, null: false
      add :embedding, :vector, size: 384
      add :threshold, :float, default: 0.8
      add :callback_url, :string, null: false

      timestamps()
    end

    create unique_index(:subscriptions, [:external_id])
    create index(:subscriptions, [:embedding])
  end
end
