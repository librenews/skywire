defmodule Skywire.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Ensure OpenSearch index exists
    Task.start(fn -> 
      Process.sleep(5000) # Wait a bit for OS to boot if running concurrently
      Skywire.Search.OpenSearch.setup() 
    end)
    
    children = [
      SkywireWeb.Telemetry,
      Skywire.Repo,
      {DNSCluster, query: Application.get_env(:skywire, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Skywire.PubSub},
      # Start the Finch HTTP client for sending emails
      # Start the Finch HTTP client for sending emails
      {Finch, name: Skywire.Finch},
      
      # ML / Embeddings (Must start before Processor so it's ready)
      Skywire.ML.Embedding,

      # Redis Client
      Skywire.Redis,
      
      # Skywire firehose components (order matters!)
      Skywire.Firehose.CursorStore,
      Skywire.Firehose.Processor,
      {Skywire.Firehose.Connection, name: Skywire.Firehose.Connection},
      
      # Data retention
      Skywire.DataTrimmer,
      
      # Start to serve requests, typically the last entry
      Skywire.LinkDetector,
      SkywireWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Skywire.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SkywireWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
