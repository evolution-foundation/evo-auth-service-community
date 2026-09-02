# frozen_string_literal: true

require 'rails_helper'

# Regression guard for the fail-closed default of
# Api::V1::ResourceActionsController#check_authorization (story RBAC 4.2 —
# retires the `true # permitir por enquanto` branch). Mirrors the probe
# pattern of users_unmapped_action_authorization_spec.
RSpec.describe 'ResourceActionsController unmapped-action authorization', type: :request do
  before(:all) do
    Api::V1::ResourceActionsController.class_eval do
      def unmapped_mutation_probe
        head :ok
      end

      def unmapped_read_probe
        head :ok
      end
    end

    Rails.application.routes.disable_clear_and_finalize = true
    Rails.application.routes.draw do
      namespace :api do
        namespace :v1 do
          # Paths avoid the resources catch-all (GET /resource_actions/:id → show).
          post 'resource_actions_probe/mutation', to: 'resource_actions#unmapped_mutation_probe'
          get 'resource_actions_probe/read', to: 'resource_actions#unmapped_read_probe'
        end
      end
    end
    Rails.application.routes.disable_clear_and_finalize = false
  end

  after(:all) do
    Rails.application.reload_routes!
    Api::V1::ResourceActionsController.send(:remove_method, :unmapped_mutation_probe)
    Api::V1::ResourceActionsController.send(:remove_method, :unmapped_read_probe)
  end

  let(:password) { 'Test123!@' }
  let(:admin_role) { Role.find_by!(key: 'super_admin') }

  def build_user(name, role: nil)
    user = User.create!(
      name: name,
      email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
    UserRole.create!(user: user, role: role) if role
    user
  end

  def headers_for(user)
    token = AccessToken.create!(owner: user, name: "tk-#{SecureRandom.hex(3)}", scopes: 'default')
    { 'api_access_token' => token.token, 'Host' => 'localhost' }
  end

  let(:roleless_user) { build_user('Roleless User') }
  let(:admin_user) { build_user('Admin User', role: admin_role) }

  it 'denies an unmapped MUTATING action (fail closed)' do
    post '/api/v1/resource_actions_probe/mutation',
         headers: headers_for(roleless_user),
         as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'leaves an unmapped read-only action ungated' do
    get '/api/v1/resource_actions_probe/read',
        headers: headers_for(roleless_user),
        as: :json

    expect(response).to have_http_status(:ok)
  end

  it 'keeps the mapped validate action denied for humans (service-only by design)' do
    # resource_actions.* is not in the catalog, so no human role holds it —
    # the mapped actions are reachable only via the service channel.
    post '/api/v1/resource_actions/validate',
         params: { permissions: [ 'users.read' ] },
         headers: headers_for(admin_user),
         as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'keeps the service-token bypass intact for an unmapped mutating action' do
    original = ENV['EVOAI_CRM_API_TOKEN']
    ENV['EVOAI_CRM_API_TOKEN'] = 'service-token-probe'

    post '/api/v1/resource_actions_probe/mutation',
         headers: { 'X-Internal-API-Token' => 'service-token-probe', 'Host' => 'localhost' },
         as: :json

    expect(response).to have_http_status(:ok)
  ensure
    ENV['EVOAI_CRM_API_TOKEN'] = original
  end
end
