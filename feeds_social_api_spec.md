# feeds.social – API Specification (Draft)

## 1. Base URLs

| Type | URL |
|------|-----|
| Public feed access | `https://feeds.social/@handle/feed.rss` |
| Canonical feed | `https://feeds.social/did-plc:XYZ/feed.rss` |
| User subdomain | `https://handle.feeds.social/feed.rss` |
| Custom domain | `https://feeds.example.com/feed.rss` |
| API root | `https://feeds.social/api/v1` |

---

## 2. Feed Types

All feeds are available in RSS, Atom, and JSONFeed formats.

| Feed | Description |
|------|-------------|
| `posts` | User posts only |
| `posts+replies` | Posts + replies |
| `media` | Posts containing media (images/video/audio) |
| `links` | Posts containing links only |
| `threads` | Aggregated threads (single feed item per thread) |

Canonical feed paths (DID-based):

```
/did-plc:XYZ/posts.rss
/did-plc:XYZ/posts.atom
/did-plc:XYZ/posts.json
/did-plc:XYZ/media.rss
```

Friendly handle redirect (302):

```
/@handle/posts.rss → /did-plc:XYZ/posts.rss
```

---

## 3. Public API Endpoints

### 3.1 Get Feed Info

**Endpoint:**

```
GET /api/v1/feeds/@handle
```

**Response:**

```json
{
  "did": "did:plc:abc123",
  "handle": "@matt.blog",
  "claimed": true,
  "feeds": {
    "posts": {
      "rss": "https://feeds.social/@matt.blog/posts.rss",
      "atom": "https://feeds.social/@matt.blog/posts.atom",
      "json": "https://feeds.social/@matt.blog/posts.json"
    },
    "media": {
      "rss": "https://feeds.social/@matt.blog/media.rss"
    },
    "links": {
      "rss": "https://feeds.social/@matt.blog/links.rss"
    }
  }
}
```

### 3.2 Bulk Feed Info

**Endpoint:**

```
GET /api/v1/feeds?handles=handle1,handle2,handle3
```

**Response:** JSON array of feed objects (same as above).

### 3.3 Feed Claiming (OAuth Required)

**Endpoint:**

```
POST /api/v1/feeds/claim
Authorization: Bearer <OAuth access token>
```

**Body (JSON):**

```json
{
  "subdomain": "matt",
  "custom_domain": "feeds.matt.blog"
}
```

**Response:**

```json
{
  "did": "did:plc:abc123",
  "handle": "@matt.blog",
  "subdomain": "matt.feeds.social",
  "custom_domain": "feeds.matt.blog",
  "feeds": {
    "posts": "https://matt.feeds.social/posts.rss",
    "media": "https://matt.feeds.social/media.rss"
  }
}
```

### 3.4 Unclaim Feed

**Endpoint:**

```
POST /api/v1/feeds/unclaim
Authorization: Bearer <OAuth access token>
```

**Body (optional JSON):**

```json
{
  "subdomain": "matt"
}
```

**Response:** `200 OK`

- Feed still exists at canonical DID URL.

---

## 4. Feed Auto-Discovery

Include in HTML landing page:

```html
<link rel="alternate" type="application/rss+xml" title="Bluesky Feed" href="/@handle/feed.rss">
<link rel="alternate" type="application/atom+xml" title="Bluesky Feed" href="/@handle/feed.atom">
<link rel="alternate" type="application/json" title="Bluesky Feed" href="/@handle/feed.json">
```

Optional `.well-known/feed` endpoint for automated discovery.

---

## 5. Real-Time Updates

### 5.1 rssCloud

Include in RSS feeds:

```xml
<cloud domain="feeds.social" port="443" path="/rsscloud" protocol="http-post" />
```

Endpoint: `POST /rsscloud` — accept subscriptions and notify subscribers on new posts.

### 5.2 WebSub

Atom and JSON feeds support WebSub push notifications.

---

## 6. Feed Item Format (RSS Example)

```xml
<item>
  <title>@handle</title>
  <link>https://bsky.app/profile/handle/post/xyz</link>
  <guid isPermaLink="false">at://did:plc:abc123/app.bsky.feed.post/xyz</guid>
  <pubDate>Fri, 13 Mar 2026 18:10:00 GMT</pubDate>
  <description>Post text</description>
  <content:encoded><![CDATA[
    <p>Post text</p>
    <img src="IMAGE_URL"/>
  ]]></content:encoded>
  <media:content url="IMAGE_URL" medium="image" type="image/jpeg"/>
  <enclosure url="IMAGE_URL" type="image/jpeg" length="0"/>
</item>
```

---

## 7. Recommended MVP Stack

- Ingestion: ATProto Firehose (Jetstream), Worker (Go / Node)
- Database: PostgreSQL
- Cache: Redis
- API: Node / Rails / Go
- CDN: Cloudflare or similar

---

## 8. Optional Future Features

- Thread aggregation
- Inbound RSS → Bluesky posts
- Hashtag feeds
- Topic/keyword feeds
- Analytics dashboards
- Feed filters for premium users

