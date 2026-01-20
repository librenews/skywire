require 'faraday'
require 'json'
require 'securerandom'

url = ENV.fetch("FIREHOSE_API_URL")
id = SecureRandom.uuid

payload = {
  external_id: id,
  query: "", 
  keywords: ["test"],
  threshold: 0.8
}

puts "Sending payload to #{url}/subscriptions..."
conn = Faraday.new(url: url) do |f|
  f.request :json
  f.response :json
  f.adapter Faraday.default_adapter
  f.headers["Authorization"] = "Bearer #{ENV["SKYWIRE_TOKEN"]}"
end

response = conn.post("subscriptions", payload)
puts "Status: #{response.status}"
puts "Body: #{JSON.pretty_generate(response.body)}"
