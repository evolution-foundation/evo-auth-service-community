# frozen_string_literal: true

# Public extension contract of evo-auth-service-community. See
# EXTENSION_POINTS.md at the repository root for the full contract.
# The three sub-modules under this namespace ship no-op or
# Devise-delegating defaults; an external consumer overrides a specific
# extension point at process start via
# EvoExtensionPoints.replace(:key) { |...| ... }.
#
# Sub-modules are autoloaded by Zeitwerk under lib/evo_extension_points/.
module EvoExtensionPoints
  KNOWN_KEYS = %i[
    auth_bridge_create_user
    auth_bridge_find_user_by_email
    auth_bridge_sign_in_user
    auth_bridge_sign_in_request
    auth_bridge_current_user
    auth_bridge_sign_out
    token_claims
    login_gate
    after_bootstrap
    extra_setup_steps
  ].freeze

  # Arity expected by each override block. Negative values follow Ruby's
  # Method#arity convention (-N means at least N-1 required positional
  # args; we also accept kwargs-only blocks where arity is the same).
  # Ruby Proc#arity for the documented block shapes (verified
  # empirically; procs collapse a `**kwargs` blob into the positional
  # count, so { |user, **context| } reports arity 1 just like { |user| }).
  #   { |email:, password:, attrs: {}| }  => 1
  #   { |user| }                          => 1
  #   { || } / { }                        => 0
  #   { |user, **context| }               => 1
  EXPECTED_ARITY = {
    auth_bridge_create_user: 1,         # |email:, password:, attrs: {}|
    auth_bridge_find_user_by_email: 1,  # |email|
    auth_bridge_sign_in_user: 1,        # |user|
    auth_bridge_sign_in_request: 2,     # |user, request|
    auth_bridge_current_user: 0,        # ||
    auth_bridge_sign_out: 1,            # |user|
    token_claims: 1,                    # |user|
    login_gate: 1,                      # |user, **context|  (proc arity = 1)
    after_bootstrap: 1,                 # |user:, payload:|   (kwargs collapse to 1)
    extra_setup_steps: 0                # ||
  }.freeze

  class << self
    # Replace the implementation of an extension point at v1.0.0.
    # Raises KeyError on an unknown key, ArgumentError if the block is
    # missing or if its arity is incompatible with the documented
    # signature. Last-write-wins. Returns nil.
    def replace(name, &block)
      raise KeyError, "unknown extension point: #{name.inspect}" unless KNOWN_KEYS.include?(name)
      raise ArgumentError, "block required for #{name.inspect}" unless block

      expected = EXPECTED_ARITY.fetch(name)
      actual = block.arity
      unless arity_compatible?(actual, expected)
        raise ArgumentError,
              "block for #{name.inspect} has arity #{actual}; expected #{expected}"
      end

      mutex.synchronize { overrides[name] = block }
      nil
    end

    # Reset a single extension point back to its community default.
    # Raises KeyError on an unknown key.
    def reset(name)
      raise KeyError, "unknown extension point: #{name.inspect}" unless KNOWN_KEYS.include?(name)

      mutex.synchronize { overrides.delete(name) }
      nil
    end

    def impl_for(name)
      overrides[name]
    end

    private

    def overrides
      @overrides ||= {}
    end

    def mutex
      @mutex ||= Mutex.new
    end

    # Ruby's Method#arity: positive N means exactly N required args; -N
    # means at least N-1 required args (rest accepted). A block defined
    # with `**kwargs` reports arity -1 even if it has no positional
    # required args. We treat a block as compatible when its arity
    # matches the expected arity exactly, OR when the expected arity is
    # negative and the actual arity is also negative and the block can
    # accept at least the required count.
    def arity_compatible?(actual, expected)
      return true if actual == expected
      return actual <= expected if expected.negative? && actual.negative?

      false
    end
  end
end
