require 'faraday'
require 'json'

url = ENV.fetch("FIREHOSE_API_URL")
# Use a new UUID to avoid collisions
id = SecureRandom.uuid

payload = {
  external_id: id,
  query: "", # Empty query
  keywords: ["bluesky"],
  threshold: 0.8
}

puts "Sending payload to #{url}/subscriptions..."
puts JSON.pretty_generate(payload)

conn = Faraday.new(url: url) do |f|
  f.request :json
  f.response :json
  f.adapter Faraday.default_adapter
  f.headers["Authorization"] = "Bearer #{ENV["SKYWIRE_TOKEN"]}"
end

response = conn.post("subscriptions", payload)
puts "Status: #{response.status}"
puts "Body: #{JSON.pretty_generate(response.body)}"
