require('dotenv').config();

module.exports = {
  port: process.env.PORT || 4001,
  feedsDomain: process.env.FEEDS_DOMAIN || 'feeds.social',
  opensearchUrl: process.env.OPENSEARCH_URL || 'http://localhost:9200',
  indexName: process.env.OPENSEARCH_INDEX || 'firehose_events'
};
