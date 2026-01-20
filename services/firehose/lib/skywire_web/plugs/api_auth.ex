defmodule SkywireWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug for authenticating API requests via Bearer token.
  """
  import Plug.Conn


  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, _token_record} <- Skywire.Auth.verify_token(token) do
      conn
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Unauthorized"})
        |> halt()
    end
  end
end
