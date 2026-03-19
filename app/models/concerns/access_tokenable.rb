module AccessTokenable
  extend ActiveSupport::Concern
  included do
    has_many :access_tokens, as: :owner, dependent: :destroy_async
  end
end
