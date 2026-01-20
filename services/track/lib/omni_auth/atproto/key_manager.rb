require "openssl"
require "json"
require "fileutils"

module OmniAuth
  module Atproto
    class KeyManager
      def self.current_private_key
        return OpenSSL::PKey::EC.new(File.read(private_key_path)) if File.exist?(private_key_path)

        generate_keys
        OpenSSL::PKey::EC.new(File.read(private_key_path))
      end

      def self.current_jwk
        return JSON.parse(File.read(jwk_path)) if File.exist?(jwk_path)

        generate_keys
        JSON.parse(File.read(jwk_path))
      end

      def self.generate_keys
        # Generate EC key pair (P-256 curve for ES256)
        key = OpenSSL::PKey::EC.generate("prime256v1")

        # Save private key
        FileUtils.mkdir_p(File.dirname(private_key_path))
        File.write(private_key_path, key.to_pem)

        # Generate JWK from public key
        public_key = key.public_key

        # Extract x and y coordinates from the EC point
        point_bn = public_key.to_bn
        point_hex = point_bn.to_s(16)

        # For P-256, the point is 65 bytes (0x04 + 32 bytes x + 32 bytes y)
        # Remove the first byte (0x04) and split into x and y
        if point_hex.length == 130 && point_hex.start_with?("04")
          x_hex = point_hex[2, 64]  # 32 bytes = 64 hex chars
          y_hex = point_hex[66, 64] # 32 bytes = 64 hex chars
        else
          # Fallback: use the same value for both
          x_hex = point_hex.rjust(64, "0")
          y_hex = point_hex.rjust(64, "0")
        end

        jwk = {
          kty: "EC",
          crv: "P-256",
          x: Base64.urlsafe_encode64([ x_hex ].pack("H*"), padding: false),
          y: Base64.urlsafe_encode64([ y_hex ].pack("H*"), padding: false),
          use: "sig",
          alg: "ES256",
          kid: SecureRandom.uuid
        }

        FileUtils.mkdir_p(File.dirname(jwk_path))
        File.write(jwk_path, JSON.pretty_generate(jwk))

        puts "Generated new AT Protocol keys"
        puts "Private key: #{private_key_path}"
        puts "JWK: #{jwk_path}"
      end

      def self.rotate_keys
        # Backup existing keys if they exist
        if File.exist?(private_key_path)
          backup_path = "#{private_key_path}.backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
          FileUtils.cp(private_key_path, backup_path)
          puts "Backed up private key to: #{backup_path}"
        end

        if File.exist?(jwk_path)
          backup_path = "#{jwk_path}.backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
          FileUtils.cp(jwk_path, backup_path)
          puts "Backed up JWK to: #{backup_path}"
        end

        generate_keys
      end

      def self.keys_exist?
        File.exist?(private_key_path) && File.exist?(jwk_path)
      end

      private

      def self.private_key_path
        Rails.root.join("config", "atproto_private_key.pem")
      end

      def self.jwk_path
        Rails.root.join("config", "atproto_jwk.json")
      end
    end
  end
end
