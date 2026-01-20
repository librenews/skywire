defmodule Skywire.Firehose.Cursor do
  @moduledoc """
  Schema for the firehose cursor table.
  Stores the last successfully processed sequence number.
  """
  use Ecto.Schema

  @primary_key {:id, :boolean, autogenerate: false, default: true}
  schema "firehose_cursor" do
    field :last_seq, :integer
  end
end
