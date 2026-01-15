defmodule SkywireWeb.HealthController do
  use SkywireWeb, :controller
  alias Skywire.Firehose.CursorStore
  # alias Skywire.Repo
  # import Ecto.Query

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
    # Lag calculation disabled as we moved away from Postgres.
    # TODO: Implement Redis/OpenSearch lag check.
    0
  end

end
