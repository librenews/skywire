defmodule SkywireWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug for authenticating API requests via Bearer token.
  """
  import Plug.Conn
  alias Skywire.Repo
  alias Skywire.Auth.Token

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, _token_record} <- verify_token(token) do
      conn
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Unauthorized"})
        |> halt()
    end
  end

  defp verify_token(token) do
    token_hash = hash_token(token)
    
    case Skywire.Redis.command(["GET", "api_token:#{token_hash}"]) do
      {:ok, nil} -> {:error, :invalid_token}
      {:ok, json_payload} ->
        case Jason.decode(json_payload) do
          {:ok, %{"active" => true} = record} -> {:ok, record}
          _ -> {:error, :invalid_token}
        end
      _ -> {:error, :redis_error}
    end
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end
end
