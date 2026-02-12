defmodule SkywireWeb.HealthController do
  use SkywireWeb, :controller
  alias Skywire.Firehose.CursorStore
  require Logger
  # alias Skywire.Repo
  # import Ecto.Query

  def index(conn, _params) do
    cursor = CursorStore.get_cursor()
    lag_seconds = calculate_lag()

    # Additional health checks
    checks = %{
      opensearch: check_opensearch(),
      redis: check_redis(),
      firehose_connected: check_firehose_process(),
      gpu_circuit_breaker: check_gpu_circuit_breaker()
    }

    all_healthy = Enum.all?(Map.values(checks), fn v -> v in [:ok, :degraded] end)
    status_code = if all_healthy, do: 200, else: 503

    json(conn |> put_status(status_code), %{
      status: if(all_healthy, do: "ok", else: "degraded"),
      last_seq: cursor,
      lag_seconds: lag_seconds,
      timestamp: DateTime.utc_now(),
      checks: checks
    })
  end

  defp calculate_lag do
    # Lag calculation disabled as we moved away from Postgres.
    # TODO: Implement Redis/OpenSearch lag check.
    0
  end

  defp check_opensearch do
    case Skywire.Search.OpenSearch.health_check() do
      :ok -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp check_redis do
    case Skywire.Redis.command(["PING"]) do
      {:ok, "PONG"} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp check_firehose_process do
    # Check if Connection process is alive
    case Process.whereis(Skywire.Firehose.Connection) do
      nil -> :error
      pid when is_pid(pid) -> :ok
    end
  end

  defp check_gpu_circuit_breaker do
    # Check GPU circuit breaker state
    case Skywire.ML.Local.get_state() do
      %{circuit_open: true} -> :degraded  # Still functioning, but degraded
      %{circuit_open: false} -> :ok
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  end
end
