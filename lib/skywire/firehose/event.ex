defmodule Skywire.Firehose.Event do
  @moduledoc """
  Schema for the firehose events table.
  Stores all events from the Bluesky firehose.
  """
  use Ecto.Schema

  @derive {Jason.Encoder, only: [:seq, :repo, :event_type, :collection, :record, :indexed_at]}
  @primary_key {:seq, :integer, autogenerate: false}
  schema "firehose_events" do
    field :repo, :string
    field :event_type, :string
    field :collection, :string
    field :record, :map
    field :indexed_at, :utc_datetime
  end
end
