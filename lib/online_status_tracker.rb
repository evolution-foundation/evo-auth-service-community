class OnlineStatusTracker
  def self.get_presence(account_id, class_name, obj_id)
    # Simplified - always return true for auth service
    true
  end

  def self.get_status(account_id, user_id)
    # Simplified - always return 'online'
    'online'
  end
end
