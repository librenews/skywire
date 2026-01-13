defmodule Skywire.Release do
  @moduledoc """
  Tasks for release management.
  """
  @app :skywire

  def migrate do
    IO.puts "No SQL migrations to run (NoSQL Mode)"
  end

  def rollback(_repo, _version) do
    IO.puts "No SQL migrations to rollback (NoSQL Mode)"
  end

  def gen_token(name) do
    load_app()
    
    # Generate a secure random token
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    # Save to Redis
    payload = Jason.encode!(%{name: name, active: true, created_at: DateTime.utc_now()})
    {:ok, "OK"} = Skywire.Redis.command(["SET", "api_token:#{token_hash}", payload])

    IO.puts("""

    ✅ Token created successfully!

    Name: #{name}
    Token: #{token}

    ⚠️  IMPORTANT: Save this token now! It will not be shown again.

    Use it in API requests:
    Authorization: Bearer #{token}
    """)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
    Application.ensure_all_started(@app)
  end
end
