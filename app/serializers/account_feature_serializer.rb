# frozen_string_literal: true

module AccountFeatureSerializer
  extend self

  def full(account_feature)
    return nil unless account_feature

    {
      id: account_feature.id,
      account_id: account_feature.account_id,
      feature_id: account_feature.feature_id,
      feature_name: account_feature.feature&.name,
      feature_key: account_feature.feature&.key,
      value: account_feature.value,
      enabled: account_feature.enabled,
      created_at: account_feature.created_at,
      updated_at: account_feature.updated_at
    }
  end
end
