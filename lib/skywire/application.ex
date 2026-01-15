defmodule Skywire.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Block startup until OpenSearch is ready (unless waiting is disabled, e.g. test)
    if Application.get_env(:skywire, :check_opensearch_on_startup, true) do
      wait_for_opensearch()
    end
    
    
    # Initialize indices (safe now)
    if Application.get_env(:skywire, :check_opensearch_on_startup, true) do
       Skywire.Search.OpenSearch.setup()
    end
    
    children = [
      SkywireWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:skywire, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Skywire.PubSub},
      # Start the Finch HTTP client for sending emails
      # Start the Finch HTTP client for sending emails
      {Finch, name: Skywire.Finch},
      
      # ML / Embeddings (Removed local Bumblebee stack)
      # Skywire.ML.Embedding,

      # Redis Client
      Skywire.Redis,
      
      # Skywire firehose components (order matters!)
      Skywire.Firehose.CursorStore
    ] ++ if Application.get_env(:skywire, :start_firehose, true) do
      [
        Skywire.Firehose.Processor,
        {Skywire.Firehose.Connection, name: Skywire.Firehose.Connection}
      ]
    else
      []
    end ++ [
      
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
  
  defp wait_for_opensearch(attempts \\ 1) do
    require Logger
    max_retries = 30
    
    if attempts > max_retries do
       Logger.error("OpenSearch failed to come up after 60 seconds. Continuing anyway, but crash is likely.")
    else
       case Skywire.Search.OpenSearch.health_check() do
         :ok -> 
           Logger.info("OpenSearch is ready.")
           :ok
         _ ->
           Logger.info("Waiting for OpenSearch... (Attempt #{attempts}/#{max_retries})")
           Process.sleep(2000)
           wait_for_opensearch(attempts + 1)
       end
    end
  end
end
