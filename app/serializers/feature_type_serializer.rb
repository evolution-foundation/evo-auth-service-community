# frozen_string_literal: true

module FeatureTypeSerializer
  extend self

  def full(feature_type)
    return nil unless feature_type

    {
      id: feature_type.id,
      name: feature_type.name,
      description: feature_type.description,
      created_at: feature_type.created_at,
      updated_at: feature_type.updated_at
    }
  end
end
