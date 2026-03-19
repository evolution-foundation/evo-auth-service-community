# frozen_string_literal: true

module PlanFeatureSerializer
  extend self

  def full(plan_feature)
    return nil unless plan_feature

    {
      id: plan_feature.id,
      plan_id: plan_feature.plan_id,
      feature_id: plan_feature.feature_id,
      feature_name: plan_feature.feature&.name,
      feature_key: plan_feature.feature&.key,
      value: plan_feature.value,
      created_at: plan_feature.created_at,
      updated_at: plan_feature.updated_at
    }
  end
end
