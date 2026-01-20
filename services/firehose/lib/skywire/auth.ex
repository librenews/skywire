defmodule Skywire.Auth do
  @moduledoc """
  Shared Logic for Token Authentication (API & WebSockets).
  """
  
  def verify_token(nil), do: {:error, :missing_token}
  def verify_token(token) do
    token_hash = hash_token(token)
    
    case Skywire.Redis.command(["GET", "api_token:#{token_hash}"]) do
      {:ok, nil} -> {:error, :invalid_token}
      {:ok, json_payload} ->
        case Jason.decode(json_payload) do
          {:ok, %{"active" => true} = record} -> {:ok, record}
          _ -> {:error, :invalid_token}
        end
      {:error, reason} -> 
        {:error, reason}
    end
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end
end
