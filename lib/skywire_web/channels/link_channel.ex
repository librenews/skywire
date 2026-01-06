defmodule SkywireWeb.LinkChannel do
  @moduledoc """
  Channel for streaming link detection events to WebSocket clients.

  Clients join the "link_events" topic and receive `"new_link"` messages
  whenever the `Skywire.LinkDetector` broadcasts a link event.
  """

  use Phoenix.Channel

  @impl true
  def join("link_events", _payload, socket) do
    # Subscribe this channel process to the PubSub topic so it receives broadcasts
    Phoenix.PubSub.subscribe(Skywire.PubSub, "link_events")
    {:ok, socket}
  end

  @impl true
  def handle_info({:link_event, payload}, socket) do
    # Push the event to the client as a "new_link" event
    push(socket, "new_link", payload)
    {:noreply, socket}
  end

  # Optional: handle unexpected messages gracefully
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}
end
