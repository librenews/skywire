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
      
      # ML / Embeddings (Local GPU)
    ] ++ if System.get_env("START_LOCAL_ML") != "false" && Application.get_env(:skywire, :start_local_ml, true) do
      [Skywire.ML.Local]
    else
      []
    end ++ [

      # Redis Client
      Skywire.Redis,
      
      # Skywire firehose components (order matters!)
      Skywire.Firehose.CursorStore
    ] ++ if System.get_env("START_FIREHOSE") != "false" && Application.get_env(:skywire, :start_firehose, true) do
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
    
    # Auto-seed HF_TOKEN from environment if present (for dev/pre-shared auth)
    if token = System.get_env("HF_TOKEN") do
       seed_token(token, "env_hf_token")
    end

    Supervisor.start_link(children, opts)
  end
  
  def seed_token(token, name) do
    # Calculate hash manually to avoid dependency loops if Auth module isn't ready (though it's pure)
    token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    payload = Jason.encode!(%{name: name, active: true, created_at: DateTime.utc_now(), auto_seeded: true})
    
    # We use a separate task to ensure Redis is up, or just fire-and-forget
    Task.start(fn -> 
      # Wait a bit for Redis to be ready if needed, usually Application order handles it but children start async
      Process.sleep(1000) 
      Skywire.Redis.command(["SET", "api_token:#{token_hash}", payload])
      require Logger
      Logger.info("🔑 Auto-seeded API token from environment: #{name} (#{String.slice(token, 0, 4)}...)")
    end)
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
