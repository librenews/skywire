defmodule SkywireWeb.SubscriptionControllerTest do
  use SkywireWeb.ConnCase, async: false
  import Mox

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!
  
  alias Skywire.ML.Mock, as: MLMock
  alias Skywire.Search.OpenSearchMock
  alias Skywire.RedisMock

  # Authentication Helper
  defp authenticate(conn) do
    # 1. Generate token and hash
    token = "test_token_123"
    hash = Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    
    # 2. Expect Redis call to verify token
    # We use stub/expect. Since tests are sequential (async: false), expect is fine.
    # Note: Plugs run before controller actions, so this expectation happens early.
    
    # We expect GET api_token:<hash> to return active JSON
    expect(RedisMock, :command, fn ["GET", "api_token:" <> ^hash] ->
       {:ok, "{\"active\": true}"}
    end)
    
    # 3. Add Header
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "POST /api/subscriptions" do
    test "creates subscription with semantic query (and embedding)", %{conn: conn} do
      conn = authenticate(conn)
      
      # 1. Expect Embedding Generation
      expect(MLMock, :generate_batch, fn ["artificial intelligence"], _model ->
        [[0.1, 0.2, 0.3]] # Return one embedding
      end)

      # 2. Expect OpenSearch Indexing
      expect(OpenSearchMock, :index_subscription, fn "sub_123", doc ->
        # For pure semantic query, it's a script query, not bool
        assert doc["query"]["script"] 
        {:ok, %{status: 201}}
      end)

      payload = %{
        "external_id" => "sub_123",
        "query" => "artificial intelligence",
        "threshold" => 0.8
      }

      conn = post(conn, ~p"/api/subscriptions", payload)
      response = json_response(conn, 201)
      
      assert response["external_id"] == "sub_123"
      assert response["status"] == "active"
    end

    test "creates subscription with keywords only (no embedding)", %{conn: conn} do
      conn = authenticate(conn)
      # No embedding generation expected for keyword-only subscription
      
      # 1. Expect OpenSearch Indexing
      expect(OpenSearchMock, :index_subscription, fn "sub_456", doc ->
        # Assert structure for keyword-only
        assert doc["threshold"] == 0.8
        {:ok, %{status: 201}}
      end)

      payload = %{
        "external_id" => "sub_456",
        "keywords" => ["elixir", "phoenix"],
        "threshold" => 0.8
      }

      conn = post(conn, ~p"/api/subscriptions", payload)
      assert json_response(conn, 201)["external_id"] == "sub_456"
    end
  end

  describe "GET /api/subscriptions/:id" do
    test "returns subscription when found", %{conn: conn} do
      conn = authenticate(conn)
      expect(OpenSearchMock, :get_subscription, fn "sub_123" ->
        {:ok, %{
          "external_id" => "sub_123",
          "threshold" => 0.9,
          "embedding" => nil
        }}
      end)

      conn = get(conn, ~p"/api/subscriptions/sub_123")
      resp = json_response(conn, 200)
      assert resp["external_id"] == "sub_123"
      assert resp["threshold"] == 0.9
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = authenticate(conn)
      expect(OpenSearchMock, :get_subscription, fn "missing" ->
        {:error, :not_found}
      end)

      conn = get(conn, ~p"/api/subscriptions/missing")
      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/subscriptions/:id" do
      test "deletes subscription", %{conn: conn} do
        conn = authenticate(conn)
        expect(OpenSearchMock, :delete_subscription, fn "sub_123" ->
          {:ok, %{}}
        end)
  
        conn = delete(conn, ~p"/api/subscriptions/sub_123")
        assert response(conn, 204)
      end
    end
end
