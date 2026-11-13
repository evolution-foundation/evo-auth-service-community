# frozen_string_literal: true

namespace :access_tokens do
  desc "Clear the stored values of API access tokens (run once every instance looks tokens up by digest)"
  task clear_values: :environment do
    filled = AccessToken.backfill_and_clear_values
    puts "access_tokens: cleared #{filled} stored value(s)"
  end
end
