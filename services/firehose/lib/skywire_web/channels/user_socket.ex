defmodule SkywireWeb.UserSocket do
  @moduledoc """
  Defines the user socket for real-time channels.

  Currently registers the `link_events` channel.
  """

  use Phoenix.Socket

  ## Channels
  channel "link_events", SkywireWeb.LinkChannel
  channel "preview", SkywireWeb.PreviewChannel

  # Transport configuration (WebSocket only)


  @impl true
  def connect(params, socket, _connect_info) do
    token = Map.get(params, "token")
    
    case Skywire.Auth.verify_token(token) do
      {:ok, _record} -> {:ok, socket}
      _ -> :error
    end
  end

  @impl true
  def id(_socket), do: nil
end
