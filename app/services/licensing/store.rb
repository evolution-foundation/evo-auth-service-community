# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'socket'

module Licensing
  class Store
    INSTANCE_FILE = '.instance'
    RUNTIME_FILE  = '.runtime.dat'

    KEY_INSTANCE_ID = 'instance_id'
    KEY_API_KEY     = 'api_key'
    KEY_TIER        = 'tier'
    KEY_CUSTOMER_ID = 'customer_id'

    def initialize(data_dir: nil)
      @data_dir = data_dir || Rails.root.to_s
    end

    def load_or_create_instance_id
      if _db?
        id = RuntimeConfig.get(KEY_INSTANCE_ID)
        if id.present? && id.length == 36
          _ensure_instance_file(id)
          return id
        end
      end

      path = _x7(INSTANCE_FILE)
      if File.exist?(path)
        id = File.read(path).strip
        if id.length == 36
          RuntimeConfig.set(KEY_INSTANCE_ID, id) if _db?
          return id
        end
      end

      id = self.class._wwq || SecureRandom.uuid
      RuntimeConfig.set(KEY_INSTANCE_ID, id) if _db?
      _0a2z(_x7(INSTANCE_FILE), id)
      id
    rescue StandardError => e
      Rails.logger.warn "[L] store: #{e.message}"
      _lid_file
    end

    def save_runtime_data(api_key:, tier:, customer_id: nil)
      raise ArgumentError, 'api_key cannot be nil or empty' if api_key.nil? || api_key.to_s.strip.empty?

      if _db?
        RuntimeConfig.set(KEY_API_KEY, api_key)
        RuntimeConfig.set(KEY_TIER, tier)
        RuntimeConfig.set(KEY_CUSTOMER_ID, customer_id.to_s) unless customer_id.nil?
      end

      _wrf(api_key: api_key, tier: tier, customer_id: customer_id)
      nil
    end

    def load_runtime_data
      if _db?
        api_key = RuntimeConfig.get(KEY_API_KEY)
        if api_key.present?
          tier        = RuntimeConfig.get(KEY_TIER)
          customer_id = RuntimeConfig.get(KEY_CUSTOMER_ID)
          _ensure_runtime_file(api_key: api_key, tier: tier, customer_id: customer_id)
          hash = { 'k' => api_key, 't' => tier }
          hash['c'] = customer_id if customer_id.present?
          return hash
        end
      end

      path = _x7(RUNTIME_FILE)
      if File.exist?(path)
        data = _lrf(path)
        if data && _db?
          RuntimeConfig.set(KEY_API_KEY, data['k'])
          RuntimeConfig.set(KEY_TIER, data['t']) if data['t']
          RuntimeConfig.set(KEY_CUSTOMER_ID, data['c'].to_s) if data['c']
        end
        return data
      end

      nil
    rescue StandardError => e
      Rails.logger.warn "[L] store: #{e.message}"
      _lrf(_x7(RUNTIME_FILE))
    end

    def remove_runtime_data
      if _db?
        RuntimeConfig.delete_key(KEY_API_KEY)
        RuntimeConfig.delete_key(KEY_TIER)
        RuntimeConfig.delete_key(KEY_CUSTOMER_ID)
      end

      path = _x7(RUNTIME_FILE)
      File.delete(path) if File.exist?(path)
      nil
    rescue StandardError
      nil
    end

    def self._wwq
      hostname = Socket.gethostname rescue ''
      mac      = _uow2 || ''
      return nil if hostname.empty? && mac.empty?

      seed  = "#{hostname}|#{mac}"
      bytes = seed.bytes
      h     = Array.new(16, 0)

      [bytes.length, 16].min.times { |i| h[i] = bytes[i] }
      bytes.drop(16).each_with_index { |b, i| h[(i + 16) % 16] ^= b }

      h[6] = (h[6] & 0x0f) | 0x40
      h[8] = (h[8] & 0x3f) | 0x80

      format('%08x-%04x-%04x-%04x-%012x',
             _8y(h[0..3]), _8y(h[4..5]), _8y(h[6..7]),
             _8y(h[8..9]), _8y(h[10..15]))
    end

    VIRTUAL_IFACE_PATTERN = /\A(lo|docker|veth|br-|virbr|vnet|tun|tap|dummy|bond)/i.freeze

    def self._uow2
      return nil unless File.directory?('/sys/class/net')

      Dir.glob('/sys/class/net/*/address').sort.each do |path|
        iface = File.basename(File.dirname(path))
        next if iface.match?(VIRTUAL_IFACE_PATTERN)

        mac = File.read(path).strip rescue next
        next unless mac.match?(/\A([0-9a-f]{2}:){5}[0-9a-f]{2}\z/i)
        next if mac == '00:00:00:00:00:00'

        return mac.downcase
      end
      nil
    rescue StandardError
      nil
    end

    private

    def _db?
      ::RuntimeConfig
      ActiveRecord::Base.connection.active? &&
        ActiveRecord::Base.connection.table_exists?('runtime_configs')
    rescue StandardError
      false
    end

    def _ensure_instance_file(id)
      path = _x7(INSTANCE_FILE)
      _0a2z(path, id) unless File.exist?(path)
    rescue StandardError => e
      Rails.logger.warn "[Store] Failed to recreate .instance file: #{e.message}"
    end

    def _ensure_runtime_file(api_key:, tier:, customer_id:)
      path = _x7(RUNTIME_FILE)
      _wrf(api_key: api_key, tier: tier, customer_id: customer_id) unless File.exist?(path)
    rescue StandardError => e
      Rails.logger.warn "[Store] Failed to recreate .runtime.dat file: #{e.message}"
    end

    def _wrf(api_key:, tier:, customer_id:)
      payload = { 'k' => api_key, 't' => tier }
      payload['c'] = customer_id unless customer_id.nil?
      _0a2z(_x7(RUNTIME_FILE), JSON.generate(payload))
    end

    def _lrf(path)
      return nil unless File.exist?(path)

      data = JSON.parse(File.read(path))
      return nil if data['k'].nil? || data['k'].empty?

      data
    rescue JSON::ParserError
      nil
    end

    def _lid_file
      path = _x7(INSTANCE_FILE)
      if File.exist?(path)
        id = File.read(path).strip
        return id if id.length == 36
      end

      id = self.class._wwq || SecureRandom.uuid
      _0a2z(path, id)
      id
    end

    def _x7(filename)
      File.join(@data_dir, filename)
    end

    def _0a2z(path, content)
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(content) }
    end

    def self._8y(bytes)
      bytes.reduce(0) { |acc, b| (acc << 8) | b }
    end
    private_class_method :_8y
  end
end
