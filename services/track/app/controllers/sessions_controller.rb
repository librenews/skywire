class SessionsController < ApplicationController
  def start
    handle = params[:handle].to_s.strip

    if handle.blank?
      redirect_to root_path, alert: "Please enter your Bluesky handle."
      return
    end

    # Remove @ if present
    handle = handle.gsub(/^@/, "")

    Rails.logger.info "🔍 Resolving Bluesky handle: #{handle}"

    # Resolve handle to DID and PDS endpoint
    resolution_result = BlueskyIdentityService.resolve_handle(handle)

    if resolution_result[:error]
      redirect_to root_path, alert: "Failed to resolve handle: #{resolution_result[:error]}"
      return
    end

    # Store in session for callback and OmniAuth setup
    session[:bluesky_handle] = handle
    session[:bluesky_did] = resolution_result[:did]
    session[:bluesky_pds_endpoint] = resolution_result[:pds_endpoint]

    Rails.logger.info "✅ Resolved handle #{handle} to DID #{resolution_result[:did]} with PDS #{resolution_result[:pds_endpoint]}"

    # Redirect to OmniAuth
    redirect_to "/auth/atproto", allow_other_host: false
  end

  def callback
    auth_hash = request.env["omniauth.auth"]

    unless auth_hash
      redirect_to root_path, alert: "Authentication failed."
      return
    end

    did = auth_hash.dig("info", "did")
    unless did
      redirect_to root_path, alert: "Could not retrieve account information."
      return
    end

    # Extract OAuth credentials
    credentials = auth_hash["credentials"] || {}

    # Try to fetch profile data (or fallback to session)
    handle = auth_hash.dig("info", "handle") || session[:bluesky_handle]
    display_name = auth_hash.dig("info", "name") || handle
    avatar_url = auth_hash.dig("info", "image")

    # If avatar is missing, try to fetch it explicitly
    if avatar_url.blank?
      Rails.logger.info "👤 Avatar missing in auth_hash, fetching profile for #{did}..."
      profile = BlueskyIdentityService.get_profile(did)
      if profile
        avatar_url = profile[:avatar]
        display_name = profile[:display_name] if display_name.blank? # Also backfill name if needed
      end
    end

    # Update or Create User
    user = User.find_or_initialize_by(did: did)
    user.update!(
      handle: handle,
      display_name: display_name,
      avatar_url: avatar_url,
      access_token: credentials["token"],
      refresh_token: credentials["refresh_token"],
      expires_at: credentials["expires_at"] ? Time.at(credentials["expires_at"]) : nil
    )

    # Log in
    session[:user_id] = user.id
    redirect_to root_path, notice: "Connected as @#{handle}!"
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Logged out."
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{params[:message]}"
  end

  def client_metadata
    # Generate client metadata JSON for OAuth registration
    rack_request = Rack::Request.new(request.env)
    scheme = rack_request.ssl? ? "https" : "http"

    if rack_request.ssl? && rack_request.port != 443
      app_url = "#{scheme}://#{rack_request.host}"
    else
      app_url = "#{scheme}://#{rack_request.host_with_port}"
    end

    client_id = "#{app_url}/oauth/client-metadata.json"

    # Ensure KeyManager is loaded
    require_relative "../../lib/omni_auth/atproto/key_manager"

    client_metadata = {
      client_id: client_id,
      application_type: "web",
      client_name: "Track",
      client_uri: app_url,
      dpop_bound_access_tokens: true,
      grant_types: [ "authorization_code", "refresh_token" ],
      redirect_uris: [ "#{app_url}/auth/atproto/callback" ],
      response_types: [ "code" ],
      scope: "atproto transition:generic transition:chat.bsky",
      token_endpoint_auth_method: "private_key_jwt",
      token_endpoint_auth_signing_alg: "ES256",
      jwks: {
        keys: [ OmniAuth::Atproto::KeyManager.current_jwk ]
      }
    }

    render json: client_metadata
  rescue => e
    Rails.logger.error "Error generating client metadata: #{e.message}"
    render json: { error: e.message }, status: 500
  end
end
