class DeliveriesController < ApplicationController
  before_action :set_track

  def index
    @deliveries = @track.deliveries.order(created_at: :desc)
    # Default to Email for the form
    @delivery = EmailDelivery.new(track: @track)
  end

  def create
    # Debug what params we are actually receiving
    Rails.logger.info "Create Delivery Params: #{params.inspect}"
    
    # Handle possible param keys from STI (email_delivery, sms_delivery, etc) or explicit 'delivery'
    permitted_params = params[:delivery] || params[:email_delivery] || params[:sms_delivery] || params[:webhook_delivery]
    
    if permitted_params.nil?
      redirect_to track_deliveries_path(@track), alert: "Invalid form data." 
      return
    end

    type = permitted_params[:type]
    klass = [EmailDelivery, SmsDelivery, WebhookDelivery].find { |k| k.name == type } || EmailDelivery
    
    @delivery = klass.new(delivery_params(permitted_params))
    @delivery.track = @track

    if @delivery.save
      redirect_to track_deliveries_path(@track), notice: "#{klass.name.titleize} added."
    else
      @deliveries = @track.deliveries.order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @delivery = @track.deliveries.find(params[:id])
    @delivery.destroy
    redirect_to track_deliveries_path(@track), notice: "Delivery method removed.", status: :see_other
  end

  private

  def set_track
    @track = current_user.tracks.find_by!(external_id: params[:track_id])
  end

  def delivery_params(p)
    p.permit(:type, :email, :frequency, :phone, :url, :secret)
  end
end
