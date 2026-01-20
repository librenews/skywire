require "redis"
redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
group = "test_group"
consumer = "test_consumer"
stream = "test_stream"

puts "Testing xgroup..."
begin
  # Attempt 1: Current usage
  redis.xgroup(:create, stream, group, "$", mkstream: true)
  puts "✅ Attempt 1 (xgroup kwargs) worked"
rescue => e
  puts "❌ Attempt 1 (xgroup kwargs) failed: #{e.message}"
end

begin
  # Attempt 2: Explicit options
  redis.xgroup(:create, stream, group + "_2", "$", { mkstream: true })
  puts "✅ Attempt 2 (xgroup explicit) worked"
rescue => e
  puts "❌ Attempt 2 (xgroup explicit) failed: #{e.message}"
end

puts "Testing xreadgroup..."
begin
  # Attempt 3: Explicit options hash
  redis.xreadgroup(group, consumer, { stream => ">" }, { count: 1, block: 100 })
  puts "✅ Attempt 3 (explicit hash) worked"
rescue ArgumentError => e
  puts "❌ Attempt 3 failed: #{e.message}"
end
