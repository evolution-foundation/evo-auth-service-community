# frozen_string_literal: true

class RuntimeConfig < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :value, presence: true

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.get_json(key)
    raw = get(key)
    raw ? JSON.parse(raw) : nil
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value.is_a?(String) ? value : value.to_json
    record.save!
  end

  def self.delete_key(key)
    find_by(key: key)&.destroy
  end

  # Atalho para o account fixo do sistema
  def self.account
    get_json('account')
  end
end
