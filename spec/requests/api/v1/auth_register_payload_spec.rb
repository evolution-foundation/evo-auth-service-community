# frozen_string_literal: true

require 'rails_helper'

# EVO-2146: register accepted only the FLAT payload ({name, email, password, ...});
# the nested {user: {...}} shape hit a NON-EXISTENT `user_params` in the concern
# (AuthHelper#create_user) => NameError => 500. This guard locks BOTH shapes.
RSpec.describe 'POST /api/v1/auth/register — payload shapes (EVO-2146)', type: :request do
  let(:password) { 'Test123!@' }

  around do |example|
    original = ENV['SMTP_ADDRESS']
    ENV.delete('SMTP_ADDRESS') # open posture: no confirmation email in the test
    example.run
  ensure
    original.nil? ? ENV.delete('SMTP_ADDRESS') : ENV['SMTP_ADDRESS'] = original
  end

  before do
    allow(Licensing::Runtime).to receive(:context).and_return(
      instance_double(Licensing::RuntimeContext, active?: true, track_message: nil)
    )
    allow(RuntimeConfig).to receive(:account).and_return(nil)
  end

  it 'creates the user with the FLAT payload (the shape the shell sends)' do
    email = "flat-#{SecureRandom.hex(4)}@example.com"
    post '/api/v1/auth/register', params: {
      name: 'Flat Shape', email: email, password: password, password_confirmation: password
    }

    expect(response).to have_http_status(:created)
    expect(User.find_by(email: email)).to be_present
  end

  it 'creates the user with the NESTED payload {user: {...}} instead of 500ing (NameError)' do
    email = "nested-#{SecureRandom.hex(4)}@example.com"
    post '/api/v1/auth/register', params: {
      user: { name: 'Nested Shape', email: email, password: password, password_confirmation: password }
    }

    expect(response).to have_http_status(:created)
    expect(User.find_by(email: email)).to be_present
  end

  it '422s (not 500) when the nested payload is missing required fields' do
    post '/api/v1/auth/register', params: { user: { name: 'No Email' } }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it '422s via the ParameterMissing rescue when the flat payload has no name (falls into the nested branch)' do
    # Without `name` the flat branch doesn't match (it requires name+password), so
    # the code falls into the else -> params.require(:user) -> ParameterMissing ->
    # rescue -> 422.
    post '/api/v1/auth/register', params: {
      email: "noname-#{SecureRandom.hex(4)}@example.com", password: password
    }

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
