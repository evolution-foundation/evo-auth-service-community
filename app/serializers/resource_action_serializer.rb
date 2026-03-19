# frozen_string_literal: true

module ResourceActionSerializer
  extend self

  def full(resource_action)
    return nil unless resource_action

    {
      id: resource_action.id,
      resource: resource_action.resource,
      actions: resource_action.actions,
      description: resource_action.description,
      created_at: resource_action.created_at,
      updated_at: resource_action.updated_at
    }
  end
end
