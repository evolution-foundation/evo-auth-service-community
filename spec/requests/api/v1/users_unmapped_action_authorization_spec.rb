# frozen_string_literal: true

require 'rails_helper'

# Regression guard for the fail-closed default of
# Api::V1::UsersController#check_authorization. An action with no entry in the
# authorization map must NOT be implicitly authorized when it mutates state.
# Throwaway probe actions + routes stand in for a future controller action a
# developer wires up but forgets to add to the map.
RSpec.describe 'UsersController unmapped-action authorization', type: :request do
  before(:all) do
    Api::V1::UsersController.class_eval do
      skip_before_action :fetch_user,
                         only: %i[unmapped_mutation_probe unmapped_read_probe],
                         raise: false

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
          post 'users/unmapped_mutation_probe', to: 'users#unmapped_mutation_probe'
          get 'users/unmapped_read_probe', to: 'users#unmapped_read_probe'
        end
      end
    end
    Rails.application.routes.disable_clear_and_finalize = false
  end

  after(:all) do
    Rails.application.reload_routes!
    Api::V1::UsersController.send(:remove_method, :unmapped_mutation_probe)
    Api::V1::UsersController.send(:remove_method, :unmapped_read_probe)
  end

  let(:password) { 'Test123!@' }

  def build_user(name)
    User.create!(
      name: name,
      email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  def headers_for(user)
    token = AccessToken.create!(owner: user, name: "tk-#{SecureRandom.hex(3)}", scopes: 'default')
    { 'api_access_token' => token.token, 'Host' => 'localhost' }
  end

  let(:roleless_user) { build_user('Roleless User') }

  it 'denies an unmapped MUTATING action (fail closed)' do
    post '/api/v1/users/unmapped_mutation_probe',
         headers: headers_for(roleless_user),
         as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'leaves an unmapped read-only action ungated (self/read endpoints keep working)' do
    get '/api/v1/users/unmapped_read_probe',
        headers: headers_for(roleless_user),
        as: :json

    expect(response).to have_http_status(:ok)
  end

  it 'keeps the service-token bypass intact for an unmapped mutating action' do
    original = ENV['EVOAI_CRM_API_TOKEN']
    ENV['EVOAI_CRM_API_TOKEN'] = 'service-token-probe'

    post '/api/v1/users/unmapped_mutation_probe',
         headers: { 'X-Internal-API-Token' => 'service-token-probe', 'Host' => 'localhost' },
         as: :json

    expect(response).to have_http_status(:ok)
  ensure
    ENV['EVOAI_CRM_API_TOKEN'] = original
  end
end
