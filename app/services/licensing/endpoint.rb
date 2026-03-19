# frozen_string_literal: true

module Licensing
  module Endpoint
    ENCODED_EP = '8ed9764008a123264dc5b24af3160d53a3eb35101ac3bc0318f463e78c564ccf26560f5aa56841be000a'.freeze
    XOR_KEY    = 'e6ad02307b9b0c0921acd12f9d65687dc69d5a7c6fb7d56c76920c92e2322dbb4f396174c6072c906278'.freeze

    def self.resolve_url
      _fuw(ENCODED_EP, XOR_KEY)
    end

    def self._fuw(encoded_hex, key_hex)
      enc_bytes = _k4(encoded_hex)
      key_bytes = _k4(key_hex)
      return '' if key_bytes.empty?

      result = enc_bytes.each_with_index.map { |b, i| b ^ key_bytes[i % key_bytes.length] }
      result.pack('C*')
    end

    def self._k4(hex_str)
      return [] if hex_str.length.odd?

      result = []
      i = 0
      while i < hex_str.length
        result << ((_4i4(hex_str[i]) << 4) | _4i4(hex_str[i + 1]))
        i += 2
      end
      result
    end

    def self._4i4(c)
      case c
      when '0'..'9' then c.ord - 48
      when 'a'..'f' then c.ord - 87
      when 'A'..'F' then c.ord - 55
      else 0
      end
    end

    private_class_method :_fuw, :_4i4, :_k4
  end
end
