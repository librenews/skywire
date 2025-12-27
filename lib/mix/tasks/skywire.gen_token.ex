defmodule Mix.Tasks.Skywire.GenToken do
  @moduledoc """
  Generates a new API token for accessing the Skywire API.

  ## Usage

      mix skywire.gen_token "My App Name"

  This will:
  - Generate a secure random token
  - Hash and store it in the database
  - Print the token (ONLY TIME IT WILL BE SHOWN)
  """
  use Mix.Task
  alias Skywire.Repo
  alias Skywire.Auth.Token

  @shortdoc "Generate a new API token"

  @impl Mix.Task
  def run([name]) do
    Mix.Task.run("app.start")

    # Generate a secure random token
    token = generate_token()
    token_hash = hash_token(token)

    # Save to database
    %Token{}
    |> Token.changeset(%{
      name: name,
      token_hash: token_hash,
      scopes: [],
      active: true
    })
    |> Repo.insert!()

    Mix.shell().info("""

    ✅ Token created successfully!

    Name: #{name}
    Token: #{token}

    ⚠️  IMPORTANT: Save this token now! It will not be shown again.

    Use it in API requests:
    Authorization: Bearer #{token}
    """)
  end

  def run(_) do
    Mix.shell().error("Usage: mix skywire.gen_token \"Token Name\"")
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end
end
