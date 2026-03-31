# == Schema Information
#
# Table name: oauth_applications
#
#  id           :bigint           not null, primary key
#  confidential :boolean          default(TRUE), not null
#  name         :string           not null
#  redirect_uri :text             not null
#  scopes       :string           default(""), not null
#  secret       :string           not null
#  trusted      :boolean          default(FALSE), not null
#  uid          :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint
#

class OauthApplication < Doorkeeper::Application
  validates :trusted, inclusion: { in: [true, false] }

  scope :dynamic_apps, -> { where('name LIKE ?', 'Dynamic OAuth -%') }
  scope :static_apps,  -> { where.not('name LIKE ?', 'Dynamic OAuth -%') }
  # RFC 7591 dynamically registered apps are identified by the "Dynamic OAuth -" name prefix
  scope :rfc7591_apps, -> { dynamic_apps }

  def display_secret
    if trusted?
      secret
    else
      secret[0..7] + ('*' * (secret.length - 8))
    end
  end

  # App registrada dinamicamente via RFC 7591 (POST /oauth/register)
  def dynamic_oauth_app?
    name&.start_with?('Dynamic OAuth -')
  end

  def static_oauth_app?
    !dynamic_oauth_app?
  end

  # Verifica se a aplicação foi registrada via RFC 7591 (sem vínculo administrativo)
  # No modelo single-account, a distinção é feita pelo prefixo do nome.
  def rfc7591_registered?
    dynamic_oauth_app?
  end

  # No modelo single-account não há seleção de account durante autorização.
  def requires_account_selection?
    false
  end
end
