class FeedGeneratorController < ApplicationController
  include JwtAuthentication
  
  skip_before_action :verify_authenticity_token
  before_action :set_json_format

  # GET /xrpc/app.bsky.feed.getFeedSkeleton
  def get_feed_skeleton
    feed_uri = params[:feed]
    limit = (params[:limit] || 50).to_i
    cursor = params[:cursor]
    
    Rails.logger.info("getFeedSkeleton request - feed: #{feed_uri}, user: #{current_user_did}, limit: #{limit}, cursor: #{cursor}")
    
    # Find user by DID
    user = User.find_by(did: current_user_did) if current_user_did
    
    if user
      # Get matches from user's tracks
      matches = get_user_matches(user, limit, cursor)
      
      feed = matches.map do |match|
        {
          post: match_to_at_uri(match)
        }
      end
      
      # Generate cursor for pagination
      next_cursor = generate_cursor(matches) if matches.any?
      
      response = { feed: feed }
      response[:cursor] = next_cursor if next_cursor
      
      render json: response
    else
      # User not found or no DID - return empty feed or hardcoded post
      Rails.logger.info("User not found for DID: #{current_user_did}")
      render json: {
        feed: []
      }
    end
  end

  # GET /xrpc/app.bsky.feed.describeFeedGenerator
  def describe_feed_generator
    did = ENV['FEED_GENERATOR_DID'] || "did:web:#{request.host}"
    feed_name = ENV['FEED_GENERATOR_NAME'] || 'skywire-feed'
    
    render json: {
      did: did,
      feeds: [
        {
          uri: "at://#{did}/app.bsky.feed.generator/#{feed_name}"
        }
      ]
    }
  end

  # GET /.well-known/did.json
  def did_json
    did = ENV['FEED_GENERATOR_DID'] || "did:web:#{request.host}"
    service_endpoint = ENV['FEED_GENERATOR_SERVICE_ENDPOINT'] || "https://#{request.host}"
    
    render json: {
      "@context": "https://www.w3.org/ns/did/v1",
      "id": did,
      "service": [
        {
          "id": "#bsky_fg",
          "type": "BskyFeedGenerator",
          "serviceEndpoint": service_endpoint
        }
      ]
    }
  end

  private

  def set_json_format
    request.format = :json
  end

  def get_user_matches(user, limit, cursor)
    # Get all matches from user's tracks
    query = Match.joins(:track)
                 .where(tracks: { user_id: user.id })
                 .order(created_at: :desc, id: :desc)

    # Apply cursor for pagination
    if cursor.present?
      timestamp, match_id = parse_cursor(cursor)
      if timestamp && match_id
        query = query.where("matches.created_at < ? OR (matches.created_at = ? AND matches.id < ?)", 
                           timestamp, timestamp, match_id)
      end
    end

    query.limit([limit, 100].min) # Cap at 100
  end

  def match_to_at_uri(match)
    # Try to get URI from match data
    if match.data.dig("post", "uri")
      match.data.dig("post", "uri")
    else
      # Construct URI from components
      author = match.data.dig("post", "author") || match.author_did
      rkey = match.data.dig("post", "uri")&.split('/')&.last || match.id.to_s
      "at://#{author}/app.bsky.feed.post/#{rkey}"
    end
  end

  def generate_cursor(matches)
    return nil if matches.empty?
    
    last = matches.last
    timestamp = last.created_at.to_i * 1000 # Convert to milliseconds
    "#{timestamp}::#{last.id}"
  end

  def parse_cursor(cursor)
    parts = cursor.split('::')
    return nil unless parts.length == 2
    
    timestamp = Time.at(parts[0].to_i / 1000.0) # Convert from milliseconds
    match_id = parts[1].to_i
    
    [timestamp, match_id]
  rescue
    nil
  end
end
