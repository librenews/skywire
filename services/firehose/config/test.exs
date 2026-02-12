import Config

# Mock Implementations
config :skywire, :opensearch_impl, Skywire.Search.OpenSearchMock
config :skywire, :redis_impl, Skywire.RedisMock
config :skywire, :ml_impl, Skywire.ML.Mock

# Disable OpenSearch startup usage in Test
config :skywire, :check_opensearch_on_startup, false

# Disable CursorStore startup usage in Test (prevents RedisMock errors on boot)
config :skywire, :load_cursor_on_startup, false

# Disable Firehose Connection in Test (prevents real data ingestion)
config :skywire, :start_firehose, false



# We don't run a server during test. If one is required,
# you can enable the server option below.
config :skywire, SkywireWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "fRWkqH8sFzo9S/p0UpQ5TX42XXjnvwMWydOWSeWOjvNZEze0JRH9i5rxsAPBbXrc",
  server: false

# In test we don't send emails
config :skywire, Skywire.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Disable Local ML startup in Test
config :skywire, :start_local_ml, false
