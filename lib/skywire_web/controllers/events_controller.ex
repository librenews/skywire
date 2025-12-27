defmodule SkywireWeb.EventsController do
  use SkywireWeb, :controller
  alias Skywire.Repo
  alias Skywire.Firehose.Event
  import Ecto.Query

  @default_limit 100
  @max_limit 1000

  def index(conn, params) do
    # Validate required params
    with {:ok, since} <- parse_since(params),
         {:ok, limit} <- parse_limit(params) do
      
      query = build_query(since, limit, params)
      events = Repo.all(query)
      
      max_seq = if length(events) > 0 do
        List.last(events).seq
      else
        since
      end

      json(conn, %{
        events: events,
        max_seq: max_seq,
        count: length(events)
      })
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  defp parse_since(%{"since" => since}) when is_binary(since) do
    case Integer.parse(since) do
      {num, ""} -> {:ok, num}
      _ -> {:error, "Invalid 'since' parameter"}
    end
  end

  defp parse_since(%{"since" => since}) when is_integer(since), do: {:ok, since}
  defp parse_since(_), do: {:error, "Missing required parameter: 'since'"}

  defp parse_limit(%{"limit" => limit}) when is_binary(limit) do
    case Integer.parse(limit) do
      {num, ""} when num > 0 and num <= @max_limit -> {:ok, num}
      {num, ""} when num > @max_limit -> {:ok, @max_limit}
      _ -> {:error, "Invalid 'limit' parameter"}
    end
  end

  defp parse_limit(%{"limit" => limit}) when is_integer(limit) do
    cond do
      limit > 0 and limit <= @max_limit -> {:ok, limit}
      limit > @max_limit -> {:ok, @max_limit}
      true -> {:error, "Invalid 'limit' parameter"}
    end
  end

  defp parse_limit(_), do: {:ok, @default_limit}

  defp build_query(since, limit, params) do
    Event
    |> where([e], e.seq > ^since)
    |> maybe_filter_event_type(params)
    |> maybe_filter_collection(params)
    |> maybe_filter_repo(params)
    |> order_by([e], asc: e.seq)
    |> limit(^limit)
  end

  defp maybe_filter_event_type(query, %{"event_type" => event_type}) do
    where(query, [e], e.event_type == ^event_type)
  end
  defp maybe_filter_event_type(query, _), do: query

  defp maybe_filter_collection(query, %{"collection" => collection}) do
    where(query, [e], e.collection == ^collection)
  end
  defp maybe_filter_collection(query, _), do: query

  defp maybe_filter_repo(query, %{"repo" => repo}) do
    where(query, [e], e.repo == ^repo)
  end
  defp maybe_filter_repo(query, _), do: query
end
