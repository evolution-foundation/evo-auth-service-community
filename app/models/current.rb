class Current < ActiveSupport::CurrentAttributes
  attribute :user, :account, :service_authenticated, :authentication_method
end
