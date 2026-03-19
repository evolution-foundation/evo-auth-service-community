# frozen_string_literal: true

require 'concurrent'
require 'digest'

module Licensing
  class RuntimeContext
    attr_reader :tier, :version

    def initialize(tier:, version:)
      @tier      = tier
      @version   = version
      @active    = Concurrent::AtomicBoolean.new(false)
      @_m0  = Concurrent::AtomicFixnum.new(0)
      @mutex     = Mutex.new
      @_i0 = nil
      @_k0     = nil
      @_h0    = nil
      @_u0     = nil
      @_t0   = nil
    end

    def active?
      @active.value
    end

    def instance_id
      @mutex.synchronize { @_i0 }
    end

    def api_key
      @mutex.synchronize { @_k0 }
    end

    def ctx_hash
      return nil unless active?
      @mutex.synchronize { @_h0 }
    end

    def reg_url
      @mutex.synchronize { @_u0 }
    end

    def reg_url=(url)
      @mutex.synchronize { @_u0 = url }
    end

    def reg_token
      @mutex.synchronize { @_t0 }
    end

    def reg_token=(token)
      @mutex.synchronize { @_t0 = token }
    end

    def activate!(api_key:, instance_id:)
      @mutex.synchronize do
        @_k0     = api_key
        @_i0 = instance_id
        @_h0    = Digest::SHA256.digest(api_key + instance_id)
      end
      @active.make_true
    end

    def deactivate!
      @active.make_false
    end

    def track_message
      @_m0.increment
    end

    def collect_and_reset_messages
      collected = 0
      @_m0.update do |current|
        collected = current
        0
      end
      collected
    end
  end
end
