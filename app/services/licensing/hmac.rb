# frozen_string_literal: true

require 'openssl'

module Licensing
  module Hmac
    def self.sign_payload(body, secret)
      OpenSSL::HMAC.hexdigest('SHA256', secret, body)
    end
  end
end
