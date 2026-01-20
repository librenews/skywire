class Match < ApplicationRecord
  belongs_to :track

  validates :data, presence: true

  def text
    data.dig("post", "text") || data.dig("post", "record", "text")
  end

  def author_did
    data.dig("post", "author")
  end

  def bsky_url
    uri = data.dig("post", "uri")
    return nil unless uri
    
    # at://did:plc:xxx/app.bsky.feed.post/rkey -> https://bsky.app/profile/:did/post/:rkey
    rkey = uri.split("/").last
    "https://bsky.app/profile/#{author_did}/post/#{rkey}"
  end

  def indexed_at
    Time.parse(data.dig("post", "indexed_at") || data.dig("post", "record", "createdAt"))
  rescue
    created_at
  end
end
