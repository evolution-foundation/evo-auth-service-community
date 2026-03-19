Rails.application.routes.draw do
  # Health check endpoints
  get '/health', to: 'health#show'    # Liveness - always 200 if app is running
  get '/ready', to: 'health#ready'     # Readiness - 200 only if dependencies ready
  get '/metrics', to: 'health#metrics' # Prometheus metrics

  # OAuth Provider routes
  use_doorkeeper do
    controllers authorizations: 'oauth_authorization'
  end

  # OAuth Management UI
  namespace :oauth do
    resources :applications do
      member do
        post :regenerate_secret
      end
    end
    get :authorized_applications
    delete 'authorized_applications/:id', to: 'authorized_applications#destroy'
  end

  # OAuth Callback routes
  get '/oauth/callback', to: 'oauth#callback'
  get '/oauth/test', to: 'oauth#test'
  get '/oauth/token_info', to: 'oauth#token_info'

  # RFC 7591 - Dynamic Client Registration
  post '/oauth/register', to: 'oauth#register'

  # OAuth Test Page
  get '/oauth/flow-test', to: redirect('/oauth-test.html')

  # Dynamic OAuth API routes
  get '/api/v1/dynamic_oauth/available_accounts', to: 'api/v1/accounts/dynamic_oauth#available_accounts'
  post '/api/v1/dynamic_oauth/validate_client', to: 'api/v1/accounts/dynamic_oauth#validate_dynamic_client'

  # AUTH STARTS
  mount_devise_token_auth_for 'User', at: 'auth', controllers: {
    confirmations: 'devise_overrides/confirmations',
    passwords: 'devise_overrides/passwords',
    sessions: 'devise_overrides/sessions',
    omniauth_callbacks: 'devise_overrides/omniauth_callbacks',
    registrations: 'devise_overrides/registrations'
  }, via: [:get, :post]

  # MFA verification route
  devise_scope :user do
    post 'mfa/verify', to: 'devise_overrides/sessions#verify_mfa'
  end

  # API Routes
  namespace :api do
    namespace :v1 do
      # Authentication endpoints
      resources :auth, only: [] do
        collection do
          post :login
          post :logout
          post :register
          get :me
          post :refresh
          post :validate
          post :forgot_password
          post :reset_password
          post :confirmation
        end
      end

      # MFA verification (login flow)
      post 'mfa/verify', to: 'auth#verify_mfa'

      # Permission check endpoint
      resources :permissions, only: [:index] do
        collection do
          post :check
        end
      end

      # Profile endpoints
      resource :profile, only: [:show, :update], controller: 'profiles' do
        put :avatar, action: :update_avatar
        put :password, action: :update_password
        delete :cancel_email_change
        post :resend_email_confirmation
        get :notifications
        put :notifications, action: :update_notifications
      end

      # MFA endpoints
      namespace :mfa do
        post :setup_totp
        post :verify_totp
        post :setup_email_otp
        post :verify_email_otp
        get :backup_codes
        post :regenerate_backup_codes
        post :disable
      end

      # User management
      resources :users, only: [:index, :show, :create, :update, :destroy] do
        collection do
          get :permissions
          post :check_permission
        end
        member do
          patch :update_password
          patch :update_mfa
        end
      end

      # Resource Actions Configuration
      resources :resource_actions, only: [:index, :show] do
        collection do
          post :validate
        end
      end

      # Data Privacy & GDPR/LGPD Compliance
      get 'data_privacy/dashboard', to: 'data_privacy#dashboard'
      get 'data_privacy/consents', to: 'data_privacy#consents'
      post 'data_privacy/consents', to: 'data_privacy#grant_consent'
      delete 'data_privacy/consents/:consent_type', to: 'data_privacy#revoke_consent'
      get 'data_privacy/export', to: 'data_privacy#export_data'
      get 'data_privacy/portability', to: 'data_privacy#data_portability'
      post 'data_privacy/deletion_request', to: 'data_privacy#request_deletion'
      post 'data_privacy/confirm_deletion', to: 'data_privacy#confirm_deletion'

      # Features management (read-only for regular users)
      resources :features, only: [:index, :show] do
        collection do
          get :types
        end
      end

      # Plans management (read-only for regular users)
      resources :plans, only: [:index, :show]

      # Active plan endpoint (uses account-id header)
      get 'active_plan', to: 'accounts#active_plan'

      # Account management (CRM-style)
      resources :accounts, only: [:show, :create, :update] do
        member do
          post :update_active_at
          get :cache_keys
          get :permissions
          get :active_plan
        end

        scope module: :accounts do
          resources :users, only: [:index, :create, :update, :destroy] do
            collection do
              post :bulk_create
            end
            member do
              get :role
              post :check_permission
            end
          end

          # Custom Roles management per account
          resources :custom_roles do
            collection do
              get :available_permissions
            end
            member do
              # Resource-level permissions
              post :add_permission
              delete :remove_permission
              put :update_permissions

              # Instance-level permissions (scopes)
              get :resource_scopes
              post :add_resource_scope
              delete :remove_resource_scope
              put :update_resource_scopes
            end
          end

          # OAuth applications per account
          resources :oauth_applications, only: [:index, :show, :create, :update, :destroy] do
            member do
              post :regenerate_secret
            end
          end

          # Access tokens per account
          resources :access_tokens, only: [:index, :show, :create, :update, :destroy] do
            member do
              patch :update_token
            end
          end
        end
      end

      # Account-scoped routes WITHOUT account_id in URL (padrão: account-id no header)
      resources :users, only: [:index, :create, :update, :destroy], controller: 'accounts/users' do
        collection do
          post :bulk_create
        end
        member do
          get :role
          post :check_permission
        end
      end

      resources :custom_roles, controller: 'accounts/custom_roles' do
        collection do
          get :available_permissions
        end
        member do
          post :add_permission
          delete :remove_permission
          put :update_permissions
          get :resource_scopes
          post :add_resource_scope
          delete :remove_resource_scope
          put :update_resource_scopes
        end
      end

      resources :oauth_applications, only: [:index, :show, :create, :update, :destroy], controller: 'accounts/oauth_applications' do
        member do
          post :regenerate_secret
        end
      end

      resources :access_tokens, only: [:index, :show, :create, :update, :destroy], controller: 'accounts/access_tokens' do
        member do
          patch :update_token
        end
      end

      # Global OAuth applications management
      resources :oauth_applications, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :regenerate_secret
        end
        collection do
          get :scopes
        end
      end

      # Access tokens management
      resources :access_tokens, only: [:index, :create, :destroy]

      resources :roles do
        collection do
          get :full
        end
      end

      # Health check
      get :health, to: 'health#show'
    end
  end


  # ----------------------------------------------------------------------
  # Routes for external service verifications
  get '.well-known/oauth-authorization-server' => 'oauth#oauth_metadata'
  get '.well-known/oauth-protected-resource' => 'oauth#oauth_protected_resource'

  # FastMCP fix - catch malformed routes
  get '.well-known/oauth-protected-resource/mcp/sse' => 'oauth#oauth_protected_resource'
  get '.well-known/oauth-authorization-server/mcp/sse' => 'oauth#oauth_metadata'

  # License management routes
  scope '/setup' do
    get '/status',   to: 'setup#status'
    get '/register', to: 'setup#register'
    get '/activate', to: 'setup#activate'
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Root path
  root to: 'api/v1/health#show'
end
