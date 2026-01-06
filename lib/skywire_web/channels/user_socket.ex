defmodule SkywireWeb.UserSocket do
  @moduledoc """
  Defines the user socket for real-time channels.

  Currently registers the `link_events` channel.
  """

  use Phoenix.Socket

  ## Channels
  channel "link_events", SkywireWeb.LinkChannel

  # Transport configuration (WebSocket only)


  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
