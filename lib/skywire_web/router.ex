defmodule SkywireWeb.Router do
  use SkywireWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SkywireWeb do
    pipe_through :api

    # Public health check
    get "/health", HealthController, :index
  end

  # Authenticated API routes
  scope "/api", SkywireWeb do
    pipe_through [:api, SkywireWeb.Plugs.ApiAuth]

    get "/events", EventsController, :index
    
    # Semantic Search
    post "/embeddings/generate", EmbeddingController, :generate
    post "/embeddings/search", EmbeddingController, :search
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:skywire, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: SkywireWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
