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

        # Add account_id and inviter_id if available (for DeviseTokenAuth compatibility)
        if options[:include_account_context] && user.respond_to?(:active_account_user) && user.active_account_user
          base_data[:account_id] = user.active_account_user.account_id
          base_data[:inviter_id] = user.active_account_user.inviter_id
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
        if GlobalConfig.get('EVOLUTION_INBOX_HMAC_KEY').present? && user.respond_to?(:hmac_identifier)
          base_data[:hmac_identifier] = user.hmac_identifier
        end

        # Optional fields
        base_data[:last_sign_in_at] = user.last_sign_in_at if options[:include_sign_in]
        base_data[:sign_in_count] = user.sign_in_count if options[:include_sign_in]
        base_data[:accounts_count] = user.accounts.count if options[:include_counts]

        # Include accounts array if requested (for DeviseTokenAuth compatibility)
        if options[:include_accounts]
          base_data[:accounts] = user.account_users.map do |account_user|
            {
              id: account_user.account_id,
              name: account_user.account.name,
              status: account_user.account.status,
              active_at: account_user.active_at,
              role: account_user.role_data,
              permissions: account_user.permissions,
              availability: account_user.availability,
              availability_status: account_user.availability_status,
              auto_offline: account_user.auto_offline
            }
          end
        end

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
      def with_role(user, account: nil)
        return nil unless user

        data = basic(user)
        
        if account
          account_user = user.account_users.find_by(account: account)
          data[:role] = account_user&.role_data
          data[:availability] = account_user&.availability
          data[:active_at] = account_user&.active_at
        else
          data[:role] = user.role_data
        end

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
          accounts_count: user.accounts.count,
          created_at: user.created_at,
          updated_at: user.updated_at,
          last_sign_in_at: user.last_sign_in_at,
          sign_in_count: user.sign_in_count
        }
      end
    end
  end

  class AccountSerializer
    class << self
      # Full account serialization with all details
      def full(account, options = {})
        return nil unless account

        data = {
          id: account.id,
          name: account.name,
          domain: account.domain,
          support_email: account.support_email,
          locale: account.locale,
          status: account.status,
          created_at: account.created_at,
          updated_at: account.updated_at
        }

        # Optional fields
        data[:settings] = account.settings if options[:include_settings]
        data[:custom_attributes] = account.custom_attributes if options[:include_attributes]

        if options[:include_role]
          data[:role] = account.role_data
        end

        if options[:include_counts]
          data[:conversations_count] = account.try(:conversations_count) || 0
          data[:inboxes_count] = account.try(:inboxes_count) || 0
          data[:users_count] = account.try(:users_count) || 0
          data[:contacts_count] = account.try(:contacts_count) || 0
        end

        data
      end

      # Basic account serialization
      def basic(account)
        return nil unless account

        {
          id: account.id,
          name: account.name,
          status: account.status
        }
      end

      # Account with role for specific user
      def with_role(account, user: nil)
        return nil unless account

        data = {
          id: account.id,
          name: account.name,
          status: account.status,
          domain: account.domain,
          locale: account.locale
        }

        if user
          account_user = user.account_users.find_by(account: account)
          data[:role] = account_user&.role_data
        end

        data
      end

      # For super admin account management
      def for_admin(account)
        return nil unless account

        {
          id: account.id,
          name: account.name,
          domain: account.domain,
          status: account.status,
          locale: account.locale,
          created_at: account.created_at,
          updated_at: account.updated_at,
          users_count: account.account_users.count,
          settings: account.settings,
          custom_attributes: account.custom_attributes,
          role: account.role_data
        }
      end
    end
  end

  class AccountUserSerializer
    class << self
      def full(account_user)
        return nil unless account_user

        {
          id: account_user.id,
          user_id: account_user.user_id,
          account_id: account_user.account_id,
          account_name: account_user.account.name,
          role: account_user.role_data,
          availability: account_user.availability,
          active_at: account_user.active_at,
          created_at: account_user.created_at,
          updated_at: account_user.updated_at
        }
      end

      def with_user(account_user)
        return nil unless account_user

        data = full(account_user)
        data[:user] = UserSerializer.basic(account_user.user)
        data
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
