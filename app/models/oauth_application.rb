class OauthApplication < Doorkeeper::Application
  validates :trusted, inclusion: { in: [true, false] }

  scope :dynamic_apps, -> { where('name LIKE ?', 'Dynamic OAuth -%') }
  scope :static_apps,  -> { where.not('name LIKE ?', 'Dynamic OAuth -%') }
  scope :rfc7591_apps, -> { dynamic_apps }

  def display_secret
    if trusted?
      secret
    else
      secret[0..7] + ('*' * (secret.length - 8))
    end
  end

  def dynamic_oauth_app?
    name&.start_with?('Dynamic OAuth -')
  end

  def static_oauth_app?
    !dynamic_oauth_app?
  end

  def rfc7591_registered?
    dynamic_oauth_app?
  end

end
