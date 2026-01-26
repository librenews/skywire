module JwtAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :extract_user_did, only: [:get_feed_skeleton]
  end

  private

  def extract_user_did
    auth_header = request.headers['Authorization']
    
    if auth_header.blank?
      Rails.logger.warn("No Authorization header present")
      @user_did = nil
      return
    end

    begin
      # Extract token from "Bearer <token>" format
      token = auth_header.split(' ').last
      
      # For now, we'll decode without verification to get the DID
      # In production, you should verify the JWT signature
      decoded = JWT.decode(token, nil, false)
      payload = decoded.first
      
      # The DID is typically in the 'iss' (issuer) claim
      @user_did = payload['iss'] || payload['sub']
      
      Rails.logger.info("Extracted user DID: #{@user_did}")
    rescue JWT::DecodeError => e
      Rails.logger.error("JWT decode error: #{e.message}")
      @user_did = nil
    rescue => e
      Rails.logger.error("Unexpected error extracting DID: #{e.message}")
      @user_did = nil
    end
  end

  def current_user_did
    @user_did
  end
end
