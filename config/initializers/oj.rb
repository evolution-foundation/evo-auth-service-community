# frozen_string_literal: true

# Oj Configuration for optimized JSON serialization
# https://github.com/ohler55/oj

require 'oj'

# Optimize Rails integration - replaces default JSON encoder with Oj
Oj.optimize_rails

# Mimic standard JSON library for maximum compatibility
Oj.mimic_JSON()

# Default options for Oj serialization
Oj.default_options = {
  # :compat mode ensures compatibility with JSON gem and ActiveSupport
  # This is the fastest mode while maintaining Rails compatibility
  mode: :compat,
  
  # Time format - use Ruby's native format for ISO8601 compatibility
  time_format: :ruby,
  
  # Convert BigDecimal to float for JSON compatibility (faster than string)
  bigdecimal_as_decimal: false,
  
  # Load BigDecimal values as BigDecimal (not float)
  bigdecimal_load: :bigdecimal,
  
  # Use string keys in output (not symbols) for JSON standard compliance
  symbol_keys: false,
  
  # Escape mode optimized for speed
  escape_mode: :json,
  
  # No indentation for maximum speed (compact JSON)
  indent: 0,
  
  # Circular reference detection disabled for speed (ensure no circular refs in code)
  circular: false,
  
  # Allow NaN and Infinity values (convert to null)
  allow_nan: true,
  
  # Microsecond precision for timestamps
  second_precision: 6,
  
  # Use as_json method on objects (Rails compatibility)
  use_as_json: true,
  
  # Nilify empty strings for cleaner JSON
  nilify: false,
  
  # Allow blank values
  allow_blank: true,
  
  # Don't ignore nil values (explicit nulls)
  ignore_nil: false,
  
  # Cache string conversions for better performance
  cache_str: -1,  # Cache all strings
  
  # Integer range - use Bignum for large integers
  integer_range: nil,
  
  # Use raw JSON for already-encoded strings (advanced optimization)
  use_raw_json: false,
  
  # Optimize for ASCII strings (faster)
  ascii_only: false
}

Rails.logger.info "Oj JSON serializer initialized with :compat mode"