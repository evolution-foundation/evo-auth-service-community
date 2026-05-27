# frozen_string_literal: true

module EvoExtensionPoints
  # AuthBridge extension point.
  #
  # Community defaults delegate to the in-tree Devise / devise_token_auth
  # stack:
  # - create_user delegates to User.create!
  # - sign_in_user delegates to Devise's sign_in helper through Warden
  #   when a controller request scope is available; otherwise no-op
  #   (no Warden proxy outside a request).
  # - current_user reads ActiveSupport::CurrentAttributes (Current.user)
  #   which the auth-service's base controller populates per request.
  #   Outside a request scope this is nil — matching the contract.
  # - sign_out clears Current.user.
  #
  # An external consumer overrides any of the four sub-keys via
  # EvoExtensionPoints.replace(:auth_bridge_*). See EXTENSION_POINTS.md
  # at the repository root.
  module AuthBridge
    VERSION = '1.1.0'

    class << self
      def create_user(email:, password:, attrs: {})
        if (impl = EvoExtensionPoints.impl_for(:auth_bridge_create_user))
          impl.call(email: email, password: password, attrs: attrs)
        else
          User.create!(email: email, password: password, **attrs)
        end
      end

      # Lookup by email, returning the User or nil. Added in v1.1.0 so
      # consumers can resolve an existing user without depending on
      # `::User` directly. Default delegates to `User.find_by(email:)`.
      def find_user_by_email(email)
        if (impl = EvoExtensionPoints.impl_for(:auth_bridge_find_user_by_email))
          impl.call(email)
        else
          User.find_by(email: email)
        end
      end

      def sign_in_user(user)
        if (impl = EvoExtensionPoints.impl_for(:auth_bridge_sign_in_user))
          impl.call(user)
        else
          default_sign_in_user(user)
        end
      end

      # Bind `user` to the current request so subsequent requests see them
      # as authenticated. Added in v1.1.0 because `sign_in_user(user)` has
      # no request scope and therefore cannot persist a session across the
      # post-redirect boundary. Default uses the Warden proxy on
      # `request.env['warden']` (Devise / devise_token_auth populate it);
      # consumers that ship their own session layer override the
      # `:auth_bridge_sign_in_request` key.
      def sign_in_request(user, request)
        if (impl = EvoExtensionPoints.impl_for(:auth_bridge_sign_in_request))
          impl.call(user, request)
        else
          default_sign_in_request(user, request)
        end
      end

      def current_user
        if (impl = EvoExtensionPoints.impl_for(:auth_bridge_current_user))
          impl.call
        else
          default_current_user
        end
      end

      def sign_out(user)
        if (impl = EvoExtensionPoints.impl_for(:auth_bridge_sign_out))
          impl.call(user)
        else
          default_sign_out(user)
        end
      end

      private

      def default_current_user
        return nil unless defined?(::Current)

        ::Current.respond_to?(:user) ? ::Current.user : nil
      end

      def default_sign_in_user(user)
        return user unless defined?(::Current)

        ::Current.user = user if ::Current.respond_to?(:user=)
        user
      end

      def default_sign_in_request(user, request)
        warden = request&.env&.[]("warden")
        if warden.respond_to?(:set_user)
          warden.set_user(user, scope: :user)
        end
        default_sign_in_user(user)
        user
      end

      def default_sign_out(user)
        return user unless defined?(::Current)

        ::Current.user = nil if ::Current.respond_to?(:user=)
        user
      end
    end
  end
end
