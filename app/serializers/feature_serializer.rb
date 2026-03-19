# frozen_string_literal: true

module FeatureSerializer
  extend self

  def full(feature)
    return nil unless feature

    {
      id: feature.id,
      name: feature.name,
      key: feature.key,
      description: feature.description,
      feature_type_id: feature.feature_type_id,
      feature_type: feature.feature_type&.name,
      enabled: feature.enabled,
      created_at: feature.created_at,
      updated_at: feature.updated_at
    }
  end

  def basic(feature)
    return nil unless feature

    {
      id: feature.id,
      name: feature.name,
      key: feature.key,
      enabled: feature.enabled
    }
  end
end
