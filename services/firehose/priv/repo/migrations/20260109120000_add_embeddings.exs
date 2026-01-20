defmodule Skywire.Repo.Migrations.AddEmbeddings do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    alter table(:firehose_events) do
      add :embedding, :vector, size: 384
    end

    # Create HNSW index for fast approximate nearest neighbor search
    execute "CREATE INDEX firehose_events_embedding_idx ON firehose_events USING hnsw (embedding vector_l2_ops)"
  end

  def down do
    execute "DROP INDEX firehose_events_embedding_idx"
    
    alter table(:firehose_events) do
      remove :embedding
    end

    # Be careful dropping extension if other tables use it, but for now it's fine
    execute "DROP EXTENSION IF EXISTS vector"
  end
end
