class DeliveryService
  def self.dispatch(delivery, match)
    new(delivery, match).dispatch
  end

  def initialize(delivery, match)
    @delivery = delivery
    @match = match
  end

  def dispatch
    case @delivery
    when EmailDelivery
      send_email
    when SmsDelivery
      send_sms
    when WebhookDelivery
      send_webhook
    end
  rescue => e
    Rails.logger.error("Failed to dispatch delivery #{@delivery.id}: #{e.message}")
  end

  private

  def send_email
    # For now, we only handle "instant". 
    # Daily/Weekly digests would be a separate Scheduled Job.
    return unless @delivery.frequency == "instant"

    MatchMailer.new_match(@delivery, @match).deliver_later
  end

  def send_sms
    # TODO: Implement SMS (Twilio?)
    Rails.logger.info("SMS dispatch not yet implemented for #{@delivery.phone}")
  end

  def send_webhook
    payload = {
      event: "match_found",
      track: {
        id: @match.track.external_id,
        name: @match.track.name
      },
      match: @match.data
    }

    # Using Faraday for simple HTTP post
    Faraday.post(@delivery.url) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.headers['X-Skywire-Secret'] = @delivery.secret if @delivery.secret.present?
      req.body = payload.to_json
    end
  end
end
