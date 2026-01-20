xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0" do
  xml.channel do
    xml.title "Track: #{@track.name}"
    xml.description "Matches for query: #{@track.query}"
    xml.link track_url(@track)

    @matches.each do |match|
      xml.item do
        xml.title match.text.truncate(50)
        xml.description match.text
        xml.pubDate match.indexed_at.rfc822
        xml.link match.bsky_url
        xml.guid match.bsky_url
        xml.author match.author_did
      end
    end
  end
end
