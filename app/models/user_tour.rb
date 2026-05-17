# == Schema Information
#
# Table name: user_tours
#
#  id           :uuid             not null, primary key
#  user_id      :uuid             not null
#  tour_key     :string           not null
#  completed_at :datetime         not null
#  status       :string           not null, default: 'completed'
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#

class UserTour < ApplicationRecord
  STATUSES = %w[completed skipped].freeze

  belongs_to :user

  validates :tour_key, presence: true
  validates :tour_key, uniqueness: { scope: :user_id, message: 'already seen by this user' }
  validates :completed_at, presence: true
  validates :status, inclusion: { in: STATUSES }
end
