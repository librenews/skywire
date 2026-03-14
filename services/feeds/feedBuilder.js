const { Feed } = require('feed');
const config = require('./config');

/**
 * Builds a Feed object from OpenSearch documents.
 * 
 * @param {string} handle The user's handle (or DID if handle not known)
 * @param {string} did The user's DID
 * @param {Array} posts Array of documents from OpenSearch
 * @param {string} feedType "posts", "media", etc.
 */
function buildFeed(handle, did, posts, feedType) {
  const feedUrl = `https://${config.feedsDomain}/@${handle}/${feedType}.rss`;
  const siteUrl = `https://bsky.app/profile/${handle}`;

  const feed = new Feed({
    title: `@${handle} on Bluesky`,
    description: `Bluesky posts for @${handle} (${feedType} feed)`,
    id: feedUrl,
    link: feedUrl,
    language: 'en',
    image: '', // Can add profile picture if resolved
    favicon: 'https://bsky.app/favicon.ico',
    copyright: '',
    updated: posts.length > 0 ? new Date(posts[0].indexed_at) : new Date(),
    generator: 'Skywire Feeds Service',
    feedLinks: {
      rss: `https://${config.feedsDomain}/@${handle}/${feedType}.rss`,
      atom: `https://${config.feedsDomain}/@${handle}/${feedType}.atom`,
      json: `https://${config.feedsDomain}/@${handle}/${feedType}.json`
    },
    author: {
      name: handle,
      link: siteUrl
    }
  });

  posts.forEach(post => {
    // at://did:plc:xyz/app.bsky.feed.post/123 -> 123
    const rkey = post.uri.split('/').pop(); 
    const postUrl = `https://bsky.app/profile/${handle}/post/${rkey}`;

    feed.addItem({
      title: post.text ? post.text.substring(0, 50) + (post.text.length > 50 ? '...' : '') : 'Post',
      id: post.uri,
      link: postUrl,
      description: post.text,
      content: post.text, // Expand this with HTML media in production
      author: [
        {
          name: handle,
          link: siteUrl
        }
      ],
      date: new Date(post.indexed_at)
    });
  });

  return feed;
}

module.exports = {
  buildFeed
};
