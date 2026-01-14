defmodule Skywire.ML.Cloudflare do
  @moduledoc """
  Client for Cloudflare Workers AI Embeddings.
  
  Uses the REST API to run the `@cf/baai/bge-small-en-v1.5` model.
  Supports batching (Cloudflare limit is ~100 docs per request or payload size limits).
  """
  require Logger

  @model "@cf/baai/bge-small-en-v1.5"
  @base_url "https://api.cloudflare.com/client/v4/accounts"

  def generate_batch(texts) do
    account_id = System.get_env("CLOUDFLARE_ACCOUNT_ID")
    api_token = System.get_env("CLOUDFLARE_API_TOKEN")

    if is_nil(account_id) or is_nil(api_token) do
      Logger.warning("Cloudflare credentials missing. Skipping embeddings.")
      nil
    else
      url = "#{@base_url}/#{account_id}/ai/run/#{@model}"
      
      headers = [
        {"Authorization", "Bearer #{api_token}"},
        {"Content-Type", "application/json"}
      ]
      
      body = %{text: texts}

      # Cloudflare rate limit is 3000 req/min (~50 req/sec).
      # We rely on the Processor to batch events (e.g. 100 at a time).
      
      case Req.post(url, headers: headers, json: body, receive_timeout: 30_000) do
        {:ok, %Req.Response{status: 200, body: %{"success" => true, "result" => %{"data" => embeddings}}}} ->
          embeddings

        {:ok, %Req.Response{status: 200, body: %{"success" => true, "result" => embeddings}}} when is_list(embeddings) ->
           # Handle case where result is directly the list (some models vary)
           embeddings

        {:ok, %Req.Response{status: 429}} ->
          Logger.warning("Cloudflare Rate Limit Exceeded (429). Skipping batch.")
          nil

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("Cloudflare AI Error #{status}: #{inspect(body)}")
          nil

        {:error, reason} ->
          Logger.error("Cloudflare Network Error: #{inspect(reason)}")
          nil
      end
    end
  end
end
