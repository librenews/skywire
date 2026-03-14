const { Client } = require('@opensearch-project/opensearch');
const config = require('./config');

const client = new Client({
  node: config.opensearchUrl,
});

/**
 * Fetch posts for a specific DID.
 * 
 * @param {string} did The user's DID (e.g., did:plc:xyz)
 * @param {string} feedType "posts", "posts+replies", "media", or "links"
 * @param {number} size Number of posts to return
 */
async function getPostsForDid(did, feedType = 'posts', size = 50) {
  const mustFilters = [
    { term: { author: did } }
  ];

  // Exclude replies if feedType is 'posts' (only top-level)
  if (feedType === 'posts' || feedType === 'media' || feedType === 'links') {
    mustFilters.push({
      bool: {
        must_not: {
          exists: { field: 'raw_record.reply' }
        }
      }
    });
  }

  if (feedType === 'media') {
    mustFilters.push({
      exists: { field: 'raw_record.embed.images' } // Simplified check for media
    });
  }

  if (feedType === 'links') {
    mustFilters.push({
      exists: { field: 'raw_record.facets' } // Needs more robust facet filtering in production, but good for MVP
    });
  }

  const query = {
    index: config.indexName,
    body: {
      size: size,
      sort: [{ indexed_at: { order: 'desc' } }],
      query: {
        bool: {
          must: mustFilters
        }
      }
    }
  };

  try {
    const response = await client.search(query);
    return response.body.hits.hits.map(hit => hit._source);
  } catch (err) {
    if (err.meta && err.meta.statusCode === 404) {
      console.warn(`Index ${config.indexName} not found.`);
      return [];
    }
    console.error('OpenSearch query error:', err);
    throw err;
  }
}

module.exports = {
  getPostsForDid
};
