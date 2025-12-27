defmodule Skywire.Release do
  @moduledoc """
  Tasks for release management.
  """
  @app :skywire

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def gen_token(name) do
    load_app()
    
    # Generate a secure random token
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    # Save to database
    {:ok, _} = Skywire.Repo.insert(%Skywire.Auth.Token{
      name: name,
      token_hash: token_hash,
      scopes: [],
      active: true
    })

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
