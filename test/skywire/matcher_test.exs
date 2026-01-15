defmodule Skywire.MatcherTest do
  use ExUnit.Case, async: false
  import Mox

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!
  setup do
    Mox.set_mox_global()
    :ok
  end

  alias Skywire.Matcher
  alias Skywire.Search.OpenSearchMock
  alias Skywire.RedisMock

  describe "check_matches/1" do
    test "dispatches matches to Redis stream" do
      # Fixture Data
      event = %{
        repo: "did:plc:123",
        collection: "app.bsky.feed.post",
        record: %{"text" => "Ruby on Rails", "uri" => "at://...", "rkey" => "999"},
        indexed_at: DateTime.utc_now()
      }
      embedding = [0.1, 0.2]
      
      events_with_embeddings = [{event, embedding}]

      # Mock OpenSearch Response (Percolator matches)
      subscription_hit = %{
        "_source" => %{
          "external_id" => "sub_1",
          "threshold" => 0.8
        },
        "_score" => 0.95
      }

      # 1. Expect OpenSearch percolation
      expect(OpenSearchMock, :percolate_batch, fn ^events_with_embeddings ->
        [{event, [subscription_hit]}]
      end)

      # 2. Expect Redis Dispatch
      # Since Matcher uses Task.start, we need to ensure the test waits or we verify async.
      # However, Mox is process-bound. If Matcher spawns a Task, that Task is a separate process.
      # To test this reliably with Mox, we usually need allow(self(), tasks).
      # But since the Task is spawned inside the function, we can't easily allow it *before* it starts unless we control the spawner.
      # OR, we set `mox_global` mode in setup.
      
      expect(RedisMock, :command, fn ["XADD", "skywire:matches", "*", "data", _json] ->
        {:ok, "123-0"}
      end)
      
      # Allow Matcher's Task to use the mocks defined in this test process
      # This is tricky because the Task gets a new PID.
      # Ideally we use `Mox.set_mox_global()` in setup block for this test case.
      
      Matcher.check_matches(events_with_embeddings)
      
      # Wait a bit for the async Task to finish (dirty, but effective for simple test)
      Process.sleep(50)
    end
  end
end
