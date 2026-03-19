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
  belongs_to :account, optional: true

  validates :account_id, presence: true, unless: :rfc7591_registered?
  validates :trusted, inclusion: { in: [true, false] }

  scope :for_account, ->(account) { where(account: account) }
  scope :dynamic_apps, -> { where('name LIKE ?', 'Dynamic OAuth -%') }
  scope :static_apps, -> { where.not('name LIKE ?', 'Dynamic OAuth -%') }
  scope :rfc7591_apps, -> { where(account_id: nil) }

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

  # Verifica se a aplicação foi registrada via RFC 7591 (sem account vinculada)
  def rfc7591_registered?
    account_id.nil?
  end

  # Verifica se precisa de seleção de account durante autorização
  def requires_account_selection?
    rfc7591_registered?
  end
end
