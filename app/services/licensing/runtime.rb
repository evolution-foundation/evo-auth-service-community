# frozen_string_literal: true

module Licensing
  module Runtime
    class << self
      def context
        $__licensing_runtime_context
      end

      def context=(ctx)
        $__licensing_runtime_context = ctx
      end

      # rehydrate_if_inactive lets a worker that activates the license make
      # the state visible to other processes (web, other workers) without a
      # full restart. Reads runtime_configs and flips the local ctx to
      # active if a persisted api_key exists.
      #
      # Returns true when the local context is active (already or after rehydration).
      def rehydrate_if_inactive
        ctx = context
        return false if ctx.nil?
        return true  if ctx.active?

        data = Store.new.load_runtime_data
        return false if data.nil? || data['k'].blank?

        instance_id = Store.new.load_or_create_instance_id
        ctx.activate!(api_key: data['k'], instance_id: instance_id)
        true
      rescue StandardError => e
        Rails.logger.warn "[Licensing::Runtime] rehydrate failed: #{e.message}"
        false
      end
    end
  end
end
