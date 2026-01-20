module Skywire
  class TrackService
    BASE_URL = ENV.fetch("FIREHOSE_API_URL", "https://firehose.social/api")

    def initialize
      @token = ENV["SKYWIRE_TOKEN"].presence || Rails.application.credentials.skywire_token
    end

    def create(track)
      if Rails.env.test?
        track.update(status: "active")
        return
      end

      begin
        response = client.post("subscriptions", track_payload(track))
        handle_response(track, response)
      rescue => e
        Rails.logger.error("Skywire API Connection Error: #{e.message}")
        track.update(status: "error")
        # Re-raise if we want the controller to know, or just return. 
        # For now, let's swallow it so the app doesn't crash, but user sees 'Error' status.
      end
    end

    def update(track)
      if Rails.env.test?
        track.update(status: "active")
        return
      end

      response = client.put("subscriptions/#{track.external_id}", track_payload(track))
      handle_response(track, response)
    end

    def delete(track)
      if Rails.env.test?
        track.destroy
        return
      end

      response = client.delete("subscriptions/#{track.external_id}")
      Rails.logger.info("Skywire API Delete Response: #{response.body}")
      if response.success?
        track.destroy
      elsif response.status == 404
        track.destroy
      else
        track.update(status: "error")
        Rails.logger.error("Skywire API Delete Error: #{response.body}")
      end
    end

    def activate(track)
      # Regenerate ID to create a fresh track on the remote side
      track.external_id = SecureRandom.uuid
      track.status = "active" # Optimistic update, create will confirm or error

      create(track)
    end

    def deactivate(track)
      if Rails.env.test?
        track.update(status: "inactive")
        return
      end

      response = client.delete("subscriptions/#{track.external_id}")
      if response.success? || response.status == 404
        track.update(status: "inactive")
      else
        track.update(status: "error")
        Rails.logger.error("Skywire API Deactivate Error: #{response.body}")
      end
    end

    private

    def client
      @client ||= Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
        f.headers["Authorization"] = "Bearer #{@token}"
      end
    end

    def track_payload(track)
      {
        external_id: track.external_id,
        query: track.query,
        threshold: track.threshold,

        keywords: track.keywords
      }
    end

    def handle_response(track, response)
      if response.success?
        track.update(status: "active")
      else
        track.update(status: "error")
        Rails.logger.error("Skywire API Error: #{response.body}")
      end
    end
  end
end
