# frozen_string_literal: true

# Centralized serializers for User, Account, and related entities
# Usage:
#   ::Serializers::UserSerializer.full(user)
#   ::Serializers::UserSerializer.basic(user)
#   ::Serializers::AccountSerializer.full(account)
module Serializers
  class UserSerializer
    class << self
      # Full user serialization with all details
      def full(user, options = {})
        return nil unless user

        base_data = {
          id: user.id,
          name: user.name,
          email: user.email,
          type: user.type,
          role: user.role_data,
          pubsub_token: user.pubsub_token,
          created_at: user.created_at,
          updated_at: user.updated_at,
          ui_settings: user.ui_settings || {}
        }

        # Add access_token if available (for DeviseTokenAuth compatibility)
        # DeviseTokenAuth creates @token which contains the token string
        if options[:include_access_token]
          # Try to get token from options first (passed from controller)
          if options[:token].present?
            base_data[:access_token] = options[:token]
          # Fallback: try to get from user's access_tokens association
          elsif user.respond_to?(:access_tokens) && user.access_tokens.any?
            base_data[:access_token] = user.access_tokens.last.token
          # Fallback: try DeviseTokenAuth's access_token method if available
          elsif user.respond_to?(:access_token) && user.access_token
            base_data[:access_token] = user.access_token.respond_to?(:token) ? user.access_token.token : user.access_token
          end
        end

        base_data.merge!(
          display_name: user.display_name,
          available_name: user.available_name,
          availability: user.availability,
          mfa_enabled: user.mfa_enabled?,
          confirmed: user.confirmed?,
          confirmed_at: user.confirmed_at,
          custom_attributes: user.custom_attributes || {},
          message_signature: user.message_signature,
          provider: user.provider,
          uid: user.uid,
          avatar_url: user.respond_to?(:avatar_url) ? user.avatar_url : nil
        )

        # Add hmac_identifier if EVOLUTION_INBOX_HMAC_KEY is present
        if GlobalConfigService.load('EVOLUTION_INBOX_HMAC_KEY').present? && user.respond_to?(:hmac_identifier)
          base_data[:hmac_identifier] = user.hmac_identifier
        end

        # Optional fields
        base_data[:last_sign_in_at] = user.last_sign_in_at if options[:include_sign_in]
        base_data[:sign_in_count] = user.sign_in_count if options[:include_sign_in]

        base_data
      end

      # Basic user serialization (for lists, references)
      def basic(user)
        return nil unless user

        {
          id: user.id,
          name: user.name,
          display_name: user.display_name,
          email: user.email,
          type: user.type,
          confirmed: user.confirmed?
        }
      end

      # Minimal user serialization (for tokens, auth responses)
      def minimal(user)
        return nil unless user

        {
          id: user.id,
          name: user.name,
          email: user.email,
          type: user.type
        }
      end

      # User with role information
      def with_role(user)
        return nil unless user

        data = basic(user)
        data[:role] = user.role_data
        data
      end

      # For super admin user management
      def for_admin(user)
        return nil unless user

        {
          id: user.id,
          name: user.name,
          display_name: user.display_name,
          email: user.email,
          type: user.type,
          role: user.role_data,
          confirmed: user.confirmed?,
          custom_attributes: user.custom_attributes,
          created_at: user.created_at,
          updated_at: user.updated_at,
          last_sign_in_at: user.last_sign_in_at,
          sign_in_count: user.sign_in_count
        }
      end
    end
  end

  # PlanSerializer stub — plans removed in community edition
  class PlanSerializer
    class << self
      def full(_account_plan)
        nil
      end
    end
  end

  class TokenSerializer
    class << self
      def oauth(token, user)
        {
          access_token: token.token,
          expires_in: token.expires_in,
          refresh_token: token.refresh_token,
          created_at: Time.at(token.created_at).iso8601,
          scopes: token.scopes.to_a,
          type: 'bearer'
        }
      end

      def access_token(token)
        {
          id: token.id,
          name: token.name,
          token: token.token,
          scopes: token.scopes,
          expires_at: nil,
          created_at: token.created_at,
          type: 'api_access_token'
        }
      end
    end
  end
end
