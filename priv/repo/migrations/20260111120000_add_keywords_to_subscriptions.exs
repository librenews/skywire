defmodule Skywire.Repo.Migrations.AddKeywordsToSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add :keywords, {:array, :string}
    end
  end
end
