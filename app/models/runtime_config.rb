# frozen_string_literal: true

class RuntimeConfig < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value.to_s
    record.save!
  end

  def self.delete_key(key)
    find_by(key: key)&.destroy
  end
end
