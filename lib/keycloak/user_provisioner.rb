# frozen_string_literal: true

module Keycloak
  # Handles JIT (Just-In-Time) user provisioning and role synchronisation
  # from a validated Keycloak JWT claims hash.
  #
  # Usage:
  #   user = Keycloak::UserProvisioner.provision!(claims)
  #
  # JIT provisioning:
  #   - Looks up User by email (claim: "email").
  #   - Creates the user if not found, with provider "keycloak" and a
  #     random password (Keycloak owns the credential, not this service).
  #   - Existing email/password users are reused as-is; their provider is
  #     not changed so local login keeps working as a fallback.
  #
  # Role sync:
  #   - Reads roles from the JWT claim path defined by KEYCLOAK_ROLES_CLAIM
  #     (default: "permissions"). Supports dot-notation for nested paths,
  #     e.g. "realm_access.roles" → claims["realm_access"]["roles"].
  #   - Adds any local Role (matched by key) that Keycloak grants.
  #   - Removes any local Role the user currently holds that Keycloak no
  #     longer grants (full sync — Keycloak is the source of truth).
  class UserProvisioner
    def self.provision!(claims)
      new(claims).provision!
    end

    def initialize(claims)
      @claims = claims
    end

    def provision!
      user = find_or_create_user!
      sync_roles!(user)
      user
    end

    private

    def find_or_create_user!
      email = @claims['email']&.strip&.downcase
      sub   = @claims['sub']
      raise Keycloak::JwtValidator::Error, 'Keycloak token is missing the email claim' if email.blank?

      if sub.present?
        user = User.find_by(keycloak_sub: sub)
        if user
          if user.email != email
            Rails.logger.info("[Keycloak::UserProvisioner] Email changed for sub=#{sub}: #{user.email} -> #{email}")
            user.update_columns(email: email, uid: email)
          end
          return user
        end
      end

      user = User.find_by(email: email)
      if user
        user.update_columns(keycloak_sub: sub) if sub.present? && user.keycloak_sub.blank?
        return user
      end

      create_user!(email, sub)
    end

    def create_user!(email, sub = nil)
      User.create!(
        email:        email,
        name:         display_name,
        provider:     'keycloak',
        password:     "#{SecureRandom.hex(24)}Kc!1",
        confirmed_at: Time.current,
        keycloak_sub: sub
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[Keycloak::UserProvisioner] create_user! failed email=#{email} errors=#{e.record.errors.full_messages}")
      raise
    end

    def display_name
      @claims['name'] ||
        @claims['preferred_username'] ||
        @claims['email']
    end

    def sync_roles!(user)
      keycloak_keys = extract_roles

      if keycloak_keys.empty?
        assign_default_role!(user)
        return
      end

      target_roles  = Role.where(key: keycloak_keys).to_a

      if target_roles.empty?
        assign_default_role!(user)
        return
      end

      current_roles = user.roles.to_a

      roles_to_add    = target_roles - current_roles
      roles_to_revoke = current_roles.select { |r| keycloak_keys.none? { |k| k == r.key } }

      roles_to_add.each    { |role| UserRole.assign_role_to_user(user, role) }
      revoke_roles!(user, roles_to_revoke) if roles_to_revoke.any?

      Rails.logger.info(
        "[Keycloak::UserProvisioner] user=#{user.email} " \
        "added=#{roles_to_add.map(&:key)} " \
        "revoked=#{roles_to_revoke.map(&:key)}"
      )
    end

    def assign_default_role!(user)
      default_role = Role.find_by(key: 'agent')
      return unless default_role

      current_roles = user.roles.to_a
      return if current_roles.include?(default_role)

      UserRole.assign_role_to_user(user, default_role)
      Rails.logger.info("[Keycloak::UserProvisioner] user=#{user.email} assigned default role: agent")
    end

    def extract_roles
      (extract_realm_roles + extract_client_roles).uniq
    end

    def extract_realm_roles
      claim_path = ENV.fetch('KEYCLOAK_ROLES_CLAIM', 'realm_access.roles')
      keys   = claim_path.split('.')
      result = keys.length == 1 ? @claims[keys.first] : @claims.dig(*keys)
      Rails.logger.info("[Keycloak::UserProvisioner] realm claim=#{claim_path} roles=#{Array(result).inspect}")
      Array(result)
    end

    def extract_client_roles
      client_id = ENV['KEYCLOAK_CLIENT_ID']
      return [] if client_id.blank?

      result = @claims.dig('resource_access', client_id, 'roles')
      Rails.logger.info("[Keycloak::UserProvisioner] client_id=#{client_id} roles=#{Array(result).inspect}")
      Array(result)
    end

    def revoke_roles!(user, roles)
      user.user_roles
          .joins(:role)
          .where(role: roles)
          .destroy_all
    end
  end
end
