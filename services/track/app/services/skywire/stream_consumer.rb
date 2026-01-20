module Skywire
  class StreamConsumer
    STREAM_KEY = "skywire:matches"
    GROUP_NAME = "track_app" # Unique consumer group for this app
    CONSUMER_NAME = "worker_#{Socket.gethostname}_#{Process.pid}"

    def self.start
      new.start
    end

    def initialize
      @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
    end

    def start
      Rails.logger.info "🎧 Starting Skywire Stream Consumer..."
      Rails.logger.info "🎧 Starting Skywire Stream Consumer..."

      begin
        # Use raw call to avoid gem version discrepancies with mkstream option
        @redis.call("XGROUP", "CREATE", STREAM_KEY, GROUP_NAME, "$", "MKSTREAM")
        Rails.logger.info "✅ Created consumer group #{GROUP_NAME}"
      rescue Redis::CommandError => e
        if e.message.include?("BUSYGROUP")
          Rails.logger.info "ℹ️ Consumer group #{GROUP_NAME} already exists"
        else
          Rails.logger.error "🚨 Group Creation Error: #{e.message}"
        end
      end
      
      loop do
        begin
          # Block for 2 seconds (2000ms) waiting for new messages
          # ">" means "give me messages this group hasn't seen yet"
          # redis-rb 5.x expects separate arrays for keys and ids
          events = @redis.xreadgroup(GROUP_NAME, CONSUMER_NAME, [STREAM_KEY], [">"], count: 50, block: 2000)

          if events && events[STREAM_KEY]
            process_events(events[STREAM_KEY])
          end
        rescue Redis::CannotConnectError => e
          Rails.logger.error "🚨 Redis Connection Error: #{e.message}. Retrying in 5s..."
          sleep 5
        rescue StandardError => e
          Rails.logger.error "🚨 Stream Error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          sleep 1
        end
      end
    end

    private

    def ensure_group_exists
      @redis.xgroup(:create, STREAM_KEY, GROUP_NAME, "$", mkstream: true)
    rescue Redis::CommandError => e
      # BUSYGROUP Consumer Group name already exists - this is expected
      unless e.message.include?("BUSYGROUP")
        Rails.logger.error "Failed to create consumer group: #{e.message}"
      end
    end

    def process_events(messages)
      messages.each do |id, fields|
        begin
          data_json = fields["data"]
          if data_json
            data = JSON.parse(data_json)
            handle_match(data)
            log_latency(data)
          else
            Rails.logger.warn "⚠️ Received message without data field: #{id}"
          end

          # Acknowledge processing
          @redis.xack(STREAM_KEY, GROUP_NAME, id)
        rescue JSON::ParserError => e
          Rails.logger.error "❌ Failed to parse JSON for message #{id}: #{e.message}"
          # We acknowledge malformed messages to avoid stuck loop, or could move to dead letter
          @redis.xack(STREAM_KEY, GROUP_NAME, id)
        rescue StandardError => e
          Rails.logger.error "❌ Error processing message #{id}: #{e.message}"
          # Do not ack if we want to retry
        end
      end

      log_buffer_status
    end

    def log_latency(data)
      if post = data["post"]
        # Prefer indexed_at as it's when the network saw it
        timestamp_str = post["indexed_at"] || post.dig("raw_record", "createdAt")
        if timestamp_str
          created_at = Time.parse(timestamp_str)
          latency = Time.current - created_at

          if latency > 60
             Rails.logger.warn "🐢 High Latency: #{latency.round(2)}s behind firehose"
          elsif latency > 5
             Rails.logger.info "⏱️ Latency: #{latency.round(2)}s"
          end
        end
      end
    rescue StandardError
      # Don't fail processing just because logging failed
    end

    def log_buffer_status
      # Only check every so often to avoid spamming Redis command
      @processed_count ||= 0
      @processed_count += 1
      return unless (@processed_count % 10).zero?

      pending = @redis.xpending(STREAM_KEY, GROUP_NAME)
      # pending returns [count, min_id, max_id, consumers]
      # Robust handling for different redis client versions return types
      pending_count = parse_pending_count(pending)

      if pending_count > 100
        Rails.logger.warn "🌊 Backlog growing: #{pending_count} pending messages"
      end
    end

    def parse_pending_count(pending)
      if pending.is_a?(Hash)
        pending["count"] || pending[:count]
      elsif pending.is_a?(Array)
        pending[0]
      else
        0
      end
    rescue
      0
    end

    def handle_match(data)
      ProcessMatchJob.perform_later(data)
    end
  end
end
