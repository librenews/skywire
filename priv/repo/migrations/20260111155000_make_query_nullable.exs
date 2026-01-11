defmodule Skywire.Repo.Migrations.MakeQueryNullable do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      modify :query, :text, null: true
    end
  end
end
