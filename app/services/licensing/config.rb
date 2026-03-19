# frozen_string_literal: true

module Licensing
  module Config
    def self.api_key
      ENV['LICENSING_API_KEY']
    end
  end
end
