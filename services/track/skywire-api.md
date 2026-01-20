# Skywire API Reference

**Base URL**: `https://skywire.social`
**WebSocket URL**: `wss://skywire.social/socket`

This document serves as the integration contract for external applications (e.g., Rails) to consume Skywire's firehose filtration service.

---

## 1. Authentication
All HTTP API endpoints require a Bearer Token.

`Authorization: Bearer <YOUR_SECRET_TOKEN>`

*(Note: Webhooks sent *from* Skywire do not currently sign requests, but rely on the secrecy of the `callback_url`.)*

---

## 2. Subscription Management (REST)

### Create Subscription
Register a new semantic search filter.

- **Endpoint**: `POST /api/subscriptions`
- **Body**:
  ```json
  {
    "external_id": "rails-db-id-123",      // Your internal ID for this alert
    "query": "ruby on rails performance",  // Optional: Semantic query
    "threshold": 0.82,                     // Optional: Defaults to 0.8
    "keywords": ["rails", "performance"]   // Optional: Match if textual match OR semantic match
  }
  ```
- **Response** (`201 Created`):
  ```json
  {
    "id": "uuid-...",
    "external_id": "rails-db-id-123",
    "status": "active"
  }
  ```

### Update Subscription
Modify criteria for an existing subscription.

- **Endpoint**: `PUT /api/subscriptions/:id`
  - *:id* matches the `external_id`.
- **Body** (all fields optional):
  ```json
  {
    "threshold": 0.9,
    "keywords": ["new", "keywords"]
  }
  ```
- **Response** (`200 OK`): Matches the Create response.

### Delete Subscription
Stop receiving events for a specific alert.

- **Endpoint**: `DELETE /api/subscriptions/:id`
  - *:id* matches the `external_id` provided during creation.
- **Response**: `204 No Content`

---

## 3. Event Consumption (Redis Streams)

Skywire outputs matches to a Redis Stream. Webhooks are no longer supported for high-volume delivery.

- **Stream Key**: `skywire:matches`
- **Field**: `data` (JSON String)

### Payload Format
The `data` field contains a JSON string with the following structure:

```json
{
  "subscription_id": "rails-db-id-123",
  "match_score": 0.89, // 1.0 if keyword match
  "post": {
    "uri": "at://did:plc:123/app.bsky.feed.post/3k...",
    "text": "Just launched a new gem for Ruby on Rails! #ruby",
    "author": "did:plc:12345...",
    "indexed_at": "2024-01-10T12:00:00Z",
    "raw_record": {
      "$type": "app.bsky.feed.post",
      "createdAt": "2024-01-10T12:00:00Z",
      "text": "Just launched a new gem for Ruby on Rails! #ruby",
      "facets": [ ... ],
      "embed": { ... }
    }
  }
}
```

### Rails / Ruby Consumer Example

Use a background worker to consume the stream.

```ruby
# app/services/skywire_consumer.rb
class SkywireConsumer
  STREAM_KEY = "skywire:matches"
  GROUP_NAME = "rails_app"
  CONSUMER_NAME = "worker_1"

  def self.start
    r = Redis.new(url: ENV.fetch("REDIS_URL"))

    # 1. Create Consumer Group (if not exists)
    begin
      r.xgroup(:create, STREAM_KEY, GROUP_NAME, "$", mkstream: true)
    rescue Redis::CommandError => e
      puts "Group already exists"
    end

    puts "🎧 Listening for matches..."

    loop do
      # Block for 2 seconds waiting for new items
      events = r.xreadgroup(GROUP_NAME, CONSUMER_NAME, { STREAM_KEY => ">" }, block: 2000, count: 10)

      events.each do |_stream, entries|
        entries.each do |id, fields|
          data = JSON.parse(fields["data"])
          process_match(data)
          r.xack(STREAM_KEY, GROUP_NAME, id)
        end
      end
    end
  end

  def self.process_match(data)
    puts "Match for #{data['subscription_id']}: #{data['post']['text']}"
  end
end
```

---

## 4. Real-time Preview (WebSocket)

Before creating a subscription, use this channel to show users a live stream of what *would* match their query.

- **Library**: Use standard `Phoenix` JS client (or any WebSocket client).
- **Topic**: `preview`

### Connection
1.  Connect to `wss://skywire.social/socket`.
2.  Join channel `preview` with the following params:
    ```json
    {
      "query": "ruby on rails",   // Optional: Semantic Query
      "threshold": 0.8,           // Optional: Default 0.8
      "keywords": ["rails", "gems"] // Optional: Keyword Filter
    }
    ```
    *Must provide either `query` or `keywords`.*

### Events
Listen for the `new_match` event.

- **Event Name**: `new_match`
- **Match Logic**: `(Score >= Threshold) OR (Keyword Match)`
- **Payload**:
  ```json
  {
    "matches": [
      {
        "score": 0.88, // 1.0 if keyword match
        "post": {
          "uri": "at://did:...",
          "text": "Rails 8 is coming!",
          "author": "did:plc:...",
          "indexed_at": "...",
          "raw_record": { ... }
        }
      }
    ]
  }
  ```

---

## 5. Health Check
Use this to verify the service is reachable.

- **Endpoint**: `GET /api/health`
- **Response**: `200 OK`