defmodule Skywire.Repo.Migrations.CreateFirehoseTables do
  use Ecto.Migration

  def change do
    # Cursor table - stores the last successfully processed sequence
    create table(:firehose_cursor, primary_key: false) do
      add :id, :boolean, primary_key: true, default: true
      add :last_seq, :bigint, null: false
    end

    # Initialize with seq 0
    execute "INSERT INTO firehose_cursor (id, last_seq) VALUES (true, 0) ON CONFLICT DO NOTHING;",
            "DELETE FROM firehose_cursor;"

    # Event log table - stores all firehose events
    create table(:firehose_events, primary_key: false) do
      add :seq, :bigint, primary_key: true
      add :repo, :text, null: false
      add :event_type, :text, null: false
      add :collection, :text
      add :record, :map
      add :indexed_at, :utc_datetime, default: fragment("now()")
    end

    # Indexes for common query patterns
    create index(:firehose_events, [:event_type])
    create index(:firehose_events, [:collection])
    create index(:firehose_events, [:repo])
    create index(:firehose_events, [:indexed_at])
  end
end
