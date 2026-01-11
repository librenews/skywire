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
    "callback_url": "https://yourapp.com/webhooks/skywire",
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

  ```

### Update Subscription
Modify criteria for an existing subscription.

- **Endpoint**: `PUT /api/subscriptions/:id`
  - *:id* matches the `external_id`.
- **Body** (all fields optional):
  ```json
  {
    "threshold": 0.9,
    "callback_url": "https://new-url.com",
    "keywords": ["new", "keywords"]
  }
  ```
- **Response** (`200 OK`): Matches the Create response.

### Delete Subscription
Stop receiving webhooks for a specific alert.

- **Endpoint**: `DELETE /api/subscriptions/:id`
  - *:id* matches the `external_id` provided during creation.
- **Response**: `204 No Content`

---

## 3. Webhook Delivery (HTTP)

When a firehose post matches a subscription, Skywire sends a POST request to your `callback_url`.

- **Method**: `POST`
- **Headers**: `Content-Type: application/json`
- **Payload**:
  ```json
  {
    "subscription_id": "rails-db-id-123",
    "match_score": 0.89,
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
- **Payload**:
  ```json
  {
    "subscription_id": "rails-db-id-123",
    "match_score": 1.0,  // 1.0 indicates a strict keyword match
    "post": { ... }
  }
  ```
- **Notes**:
  - **Match Logic**: `(Semantic Score >= Threshold) OR (Any Keyword Match)`.
  - If a keyword matches, the `match_score` is set to `1.0`.
  - You must provide either a `query` or `keywords` (or both).
  - `raw_record` contains the exact JSON received from the Bluesky firehose.

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
      "query": "ruby on rails",
      "threshold": 0.8
    }
    ```

### Events
Listen for the `new_match` event.

- **Event Name**: `new_match`
- **Payload**:
  ```json
  {
    "matches": [
      {
        "score": 0.88,
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
