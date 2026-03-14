const express = require('express');
const cors = require('cors');
const { getPostsForDid } = require('./search');
const { buildFeed } = require('./feedBuilder');
const config = require('./config');

const app = express();

app.use(cors());
app.use(express.json());

// Basic health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', time: new Date() });
});

// --- HELPER: Resolve handle to DID (Simplified for MVP, ideally queries PLC/AppView) ---
// Since we only have OpenSearch, we'll try to find any post by the given handle to get its DID.
// Or we just query by handle (OpenSearch author field often contains DID, but sometimes we need resolution).
// For MVP, we assume `author` field in OpenSearch is the DID! 
// We will need a real handle resolution step here usually, contacting `https://bsky.social/xrpc/com.atproto.identity.resolveHandle`.

async function resolveHandle(handle) {
  if (handle.startsWith('did:')) return handle;
  
  // Real implementation for Bluesky handle resolution
  const cleanHandle = handle.replace(/^@/, '');
  try {
    const res = await fetch(`https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=${cleanHandle}`);
    if (!res.ok) {
      if (res.status === 400) return null; // Not found
      throw new Error(`Failed to resolve handle: ${res.statusText}`);
    }
    const data = await res.json();
    return data.did;
  } catch (err) {
    console.error(`Error resolving handle ${handle}:`, err);
    return null;
  }
}

// --- 1. API: Get Feed Info ---
app.get('/api/v1/feeds/:handle', async (req, res) => {
  const handleOrDid = req.params.handle;
  const did = await resolveHandle(handleOrDid);
  
  if (!did) {
    return res.status(404).json({ error: 'Handle not found' });
  }

  // Determine standard handle format
  const cleanHandle = handleOrDid.startsWith('@') ? handleOrDid : (handleOrDid.startsWith('did:') ? did : `@${handleOrDid}`);
  
  res.json({
    did: did,
    handle: cleanHandle,
    claimed: false, // Stub for future DB claiming
    feeds: {
      posts: {
        rss: `https://${config.feedsDomain}/${cleanHandle}/posts.rss`,
        atom: `https://${config.feedsDomain}/${cleanHandle}/posts.atom`,
        json: `https://${config.feedsDomain}/${cleanHandle}/posts.json`
      },
      media: {
        rss: `https://${config.feedsDomain}/${cleanHandle}/media.rss`
      },
      links: {
        rss: `https://${config.feedsDomain}/${cleanHandle}/links.rss`
      }
    }
  });
});

// --- 2. Feed Endpoints ---
// Supports /did:plc:xyz/posts.rss or /@handle/posts.rss
app.get('/:identifier/:feedName.:format', async (req, res) => {
  const { identifier, feedName, format } = req.params;
  
  // Validate format
  if (!['rss', 'atom', 'json'].includes(format)) {
    return res.status(400).send('Invalid format. Supported: rss, atom, json');
  }

  // Validate feedName
  if (!['posts', 'posts+replies', 'media', 'links'].includes(feedName)) {
    return res.status(400).send('Invalid feed type.');
  }

  const did = await resolveHandle(identifier);
  if (!did) {
    return res.status(404).send('User not found.');
  }

  // Redirect handle to canonical DID path as per spec
  // e.g., /@handle/posts.rss -> /did:plc:XYZ/posts.rss
  if (!identifier.startsWith('did:')) {
    return res.redirect(302, `/${did}/${feedName}.${format}`);
  }

  try {
    const posts = await getPostsForDid(did, feedName);
    const feed = buildFeed(identifier, did, posts, feedName);

    if (format === 'rss') {
      res.type('application/rss+xml');
      res.send(feed.rss2());
    } else if (format === 'atom') {
      res.type('application/atom+xml');
      res.send(feed.atom1());
    } else if (format === 'json') {
      res.type('application/json');
      res.send(feed.json1());
    }
  } catch (err) {
    console.error('Error generating feed:', err);
    res.status(500).send('Internal Server Error');
  }
});

// For back-compat with the spec that mentions `feed.rss`
app.get('/:identifier/feed.:format', (req, res) => {
  res.redirect(302, `/${req.params.identifier}/posts.${req.params.format}`);
});

app.listen(config.port, () => {
  console.log(`Feeds service listing on port ${config.port}`);
  console.log(`Domain currently configured as: ${config.feedsDomain}`);
});
