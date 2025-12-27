defmodule SkywireWeb.HealthController do
  use SkywireWeb, :controller
  alias Skywire.Firehose.CursorStore
  alias Skywire.Repo
  import Ecto.Query

  def index(conn, _params) do
    cursor = CursorStore.get_cursor()
    
    # Calculate lag by checking the most recent event
    lag_seconds = calculate_lag()

    json(conn, %{
      status: "ok",
      last_seq: cursor,
      lag_seconds: lag_seconds,
      timestamp: DateTime.utc_now()
    })
  end

  defp calculate_lag do
    query = from e in "firehose_events",
            select: e.indexed_at,
            order_by: [desc: e.indexed_at],
            limit: 1

    case Repo.one(query) do
      nil -> 0
      indexed_at ->
        DateTime.diff(DateTime.utc_now(), indexed_at, :second)
    end
  end
end
