require_relative "../../lib/omni_auth/atproto/key_manager"

Rails.application.config.middleware.use OmniAuth::Builder do
  # Use the omniauth-atproto strategy with dynamic configuration
  provider(:atproto,
    nil,  # Client ID will be set dynamically in the strategy
    nil,  # Client secret (not used with DPoP)
    client_options: {
        site: "https://bsky.social",
        authorize_url: "https://bsky.social/oauth/authorize",
        token_url: "https://bsky.social/oauth/token"
    },
    scope: "atproto transition:generic transition:chat.bsky",
    private_key: OmniAuth::Atproto::KeyManager.current_private_key,
    client_jwk: OmniAuth::Atproto::KeyManager.current_jwk,
    setup: proc { |env|
      # Set client_id dynamically based on current request
      request = Rack::Request.new(env)
      scheme = request.ssl? ? "https" : "http"

      if request.ssl? && request.port != 443
        app_url = "#{scheme}://#{request.host}"
      else
        app_url = "#{scheme}://#{request.host_with_port}"
      end

      client_id = "#{app_url}/oauth/client-metadata.json"
      env["omniauth.strategy"].options.client_id = client_id

      # Get PDS endpoint from session (set by SessionsController#create)
      session = env["rack.session"]
      pds_endpoint = session&.[]("bluesky_pds_endpoint")

      # Determine OAuth server based on PDS endpoint
      use_main_oauth = false

      if pds_endpoint.present?
        uri = URI(pds_endpoint)
        host = uri.host

        if host == "bsky.social" || host.end_with?(".bsky.network")
          use_main_oauth = true
        end
      else
        use_main_oauth = true # Default fallback
      end

      if use_main_oauth
        Rails.logger.info "🔧 Using main bsky.social OAuth for PDS: #{pds_endpoint}"
        env["omniauth.strategy"].options.client_options[:site] = "https://bsky.social"
        env["omniauth.strategy"].options.client_options[:authorize_url] = "https://bsky.social/oauth/authorize"
        env["omniauth.strategy"].options.client_options[:token_url] = "https://bsky.social/oauth/token"
      else
        Rails.logger.info "🔧 Using custom PDS OAuth endpoint: #{pds_endpoint}"
        env["omniauth.strategy"].options.client_options[:site] = pds_endpoint
        env["omniauth.strategy"].options.client_options[:authorize_url] = "#{pds_endpoint}/oauth/authorize"
        env["omniauth.strategy"].options.client_options[:token_url] = "#{pds_endpoint}/oauth/token"
      end
    })
end

# Configure OmniAuth settings
OmniAuth.config.allowed_request_methods = [ :post, :get ]
OmniAuth.config.silence_get_warning = true
