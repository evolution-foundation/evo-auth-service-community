module AvailabilityStatusable
  extend ActiveSupport::Concern

  def online_presence?
    # Simplified for auth service
    true
  end

  def availability_status
    # Simplified - just return the availability setting
    availability || 'online'
  end
end
