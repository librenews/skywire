xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0" do
  xml.channel do
    xml.title "Skywire Feed"
    xml.description "All matches for your monitored tracks."
    xml.link root_url

    @matches.each do |match|
      xml.item do
        xml.title "Match for: #{match.track.name}"
        xml.description match.text
        xml.pubDate match.indexed_at.rfc822
        xml.link match.bsky_url
        xml.guid match.bsky_url
        xml.author match.author_did
      end
    end
  end
end
