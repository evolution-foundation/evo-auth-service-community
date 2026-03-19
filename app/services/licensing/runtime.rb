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
    end
  end
end
