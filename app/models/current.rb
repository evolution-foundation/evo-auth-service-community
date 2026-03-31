class Current < ActiveSupport::CurrentAttributes
  attribute :user, :service_authenticated, :authentication_method
end
