class ProcessMatchJob < ApplicationJob
  queue_as :default

  def perform(data)
    subscription_external_id = data["subscription_id"]
    track = Track.find_by(external_id: subscription_external_id)

    if track
      Rails.logger.info "✅ Match for Track ##{track.id} (#{track.query})"
      
      # Persist the match
      match = Match.create!(track: track, data: data)

      # Dispatch Deliveries
      track.deliveries.where(active: true).find_each do |delivery|
        DeliveryService.dispatch(delivery, match)
      end
    else
      Rails.logger.warn "⚠️ Match received for unknown track: #{subscription_external_id}"
    end
  end
end
