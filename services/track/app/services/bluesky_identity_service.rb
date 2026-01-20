class BlueskyIdentityService
  require "net/http"
  require "json"

  # Resolve a handle to DID and PDS endpoint
  # @param handle [String] Bluesky handle (e.g., "username.bsky.social" or "@username.example.com")
  # @return [Hash] { did: "...", pds_endpoint: "https://..." } or { error: "..." }
  def self.resolve_handle(handle)
    # Clean handle (remove @ if present)
    clean_handle = handle.to_s.gsub(/^@/, "").strip

    # Use the public AT Protocol resolver endpoint
    # This is typically available at bsky.social for resolution
    resolver_endpoint = "https://bsky.social/xrpc/com.atproto.identity.resolveHandle"
    uri = URI(resolver_endpoint)
    uri.query = URI.encode_www_form({ handle: clean_handle })

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request["Content-Type"] = "application/json"

    response = http.request(request)

    unless response.code == "200"
      Rails.logger.error "Failed to resolve handle #{clean_handle}: #{response.code} #{response.body}"
      return { error: "Failed to resolve handle: #{response.code}" }
    end

    data = JSON.parse(response.body)
    did = data["did"]

    unless did.present?
      Rails.logger.error "No DID found in response for handle #{clean_handle}"
      return { error: "No DID found for handle" }
    end

    # Now resolve DID to get PDS endpoint
    pds_endpoint = resolve_did_to_pds(did)

    if pds_endpoint
      Rails.logger.info "✅ Resolved handle #{clean_handle} to DID #{did} with PDS #{pds_endpoint}"
      { did: did, pds_endpoint: pds_endpoint, handle: clean_handle }
    else
      # Fallback to default PDS if we can't determine
      Rails.logger.warn "⚠️ Could not determine PDS for DID #{did}, using default"
      { did: did, pds_endpoint: "https://bsky.social", handle: clean_handle }
    end
  rescue => e
    Rails.logger.error "Error resolving handle #{handle}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    { error: "Resolution failed: #{e.message}" }
  end

  # Fetch profile data (avatar, display name) for a DID
  # @param did [String] DID
  # @return [Hash] { avatar: "...", display_name: "..." } or nil
  def self.get_profile(did)
    # Use public API
    endpoint = "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile"
    uri = URI(endpoint)
    uri.query = URI.encode_www_form({ actor: did })

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 5

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.code == "200"
      data = JSON.parse(response.body)
      {
        avatar: data["avatar"],
        display_name: data["displayName"]
      }
    else
      Rails.logger.warn "Failed to fetch profile for #{did}: #{response.code}"
      nil
    end
  rescue => e
    Rails.logger.error "Error fetching profile for #{did}: #{e.message}"
    nil
  end

  private

  # Resolve DID to PDS endpoint
  # @param did [String] DID (e.g., "did:plc:abc123...")
  # @return [String] PDS endpoint URL or nil
  def self.resolve_did_to_pds(did)
    # Extract DID method
    did_parts = did.split(":")
    return nil unless did_parts.length >= 3

    method = did_parts[1] # e.g., "plc", "web"

    case method
    when "plc"
      # PLC DIDs use the AT Protocol Directory service
      # The PDS endpoint is typically stored in the DID document
      resolve_plc_did(did)
    when "web"
      # Web DIDs can have PDS in the DID document
      resolve_web_did(did)
    else
      # For other DID methods, try to get from directory or default
      Rails.logger.warn "Unknown DID method: #{method}"
      "https://bsky.social" # Default fallback
    end
  end

  # Resolve PLC DID (Bluesky's default DID method)
  def self.resolve_plc_did(did)
    # PLC DIDs are resolved via the AT Protocol Directory
    # Try to get DID document from directory.bsky.app
    directory_endpoint = "https://plc.directory/#{did}"

    begin
      uri = URI(directory_endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 5

      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      if response.code == "200"
        data = JSON.parse(response.body)

        # Look for PDS endpoint in service endpoints
        if data["service"]
          pds_service = data["service"].find { |s| s["type"] == "AtprotoPersonalDataServer" }
          if pds_service && pds_service["serviceEndpoint"]
            return pds_service["serviceEndpoint"]
          end
        end

        # Also check if there's a direct PDS field
        if data["pds"]
          return data["pds"]
        end
      end
    rescue => e
      Rails.logger.warn "Failed to resolve PLC DID document: #{e.message}"
    end

    # Fallback: for most users on bsky.social, the PDS is bsky.social
    # For custom domains, we might need to infer from handle domain
    "https://bsky.social"
  end

  # Resolve Web DID (for custom domain users)
  def self.resolve_web_did(did)
    # Web DIDs have the format: did:web:domain.com:path
    # Extract domain and construct well-known URL
    web_parts = did.split(":")
    return "https://bsky.social" if web_parts.length < 3

    domain = web_parts[2]

    # Try to get DID document from well-known location
    well_known_url = "https://#{domain}/.well-known/did.json"

    begin
      uri = URI(well_known_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 5

      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      if response.code == "200"
        data = JSON.parse(response.body)

        # Look for PDS endpoint in service endpoints
        if data["service"]
          pds_service = data["service"].find { |s| s["type"] == "AtprotoPersonalDataServer" }
          if pds_service && pds_service["serviceEndpoint"]
            return pds_service["serviceEndpoint"]
          end
        end
      end
    rescue => e
      Rails.logger.warn "Failed to resolve Web DID document: #{e.message}"
    end

    # Fallback: if custom domain, might be hosting their own PDS
    # But we don't know the port, so default to bsky.social
    "https://bsky.social"
  end
end
