defmodule Skywire.DataTrimmer do
  @moduledoc """
  Periodic job to trim old firehose events.
  
  Runs daily to delete events older than the configured retention period.
  Default retention: 7 days
  """
  use GenServer
  require Logger
  # alias Skywire.Repo
  # import Ecto.Query

  @trim_interval_ms :timer.hours(24)  # Run daily
  @default_retention_days 7

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule first trim
    schedule_trim()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:trim, state) do
    trim_old_events()
    schedule_trim()
    {:noreply, state}
  end

  defp schedule_trim do
    Process.send_after(self(), :trim, @trim_interval_ms)
  end

  defp trim_old_events do
    # retention_days = Application.get_env(:skywire, :event_retention_days, @default_retention_days)
    # TODO: Implement deletion from OpenSearch if needed.
    # For now, OpenSearch index lifecycle management (ILM) is preferred over manual deletion.
    Logger.info("DataTrimmer: Manual trimming is disabled in favor of ILM.")
    :ok
  end
end
