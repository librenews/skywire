defmodule SkywireWeb.UserSocketTest do
  use SkywireWeb.ChannelCase, async: false
  alias SkywireWeb.UserSocket
  import Mox

  setup :verify_on_exit!

  test "socket authentication: fails without token" do
    assert :error = connect(UserSocket, %{})
  end

  test "socket authentication: fails with invalid token" do
    token = "invalid_token"
    hash = Base.encode16(:crypto.hash(:sha256, token), case: :lower)

    # Redis returns nil
    expect(Skywire.RedisMock, :command, fn ["GET", "api_token:" <> ^hash] ->
      {:ok, nil} 
    end)

    assert :error = connect(UserSocket, %{"token" => token})
  end

  test "socket authentication: succeeds with valid token" do
    token = "valid_token"
    hash = Base.encode16(:crypto.hash(:sha256, token), case: :lower)

    # Redis returns active
    expect(Skywire.RedisMock, :command, fn ["GET", "api_token:" <> ^hash] ->
      {:ok, "{\"active\": true}"}
    end)

    assert {:ok, socket} = connect(UserSocket, %{"token" => token})
    assert socket.id == nil
  end
end
