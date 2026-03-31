module CacheKeysHelper
  def get_prefixed_cache_key(entity_id, key)
    "idb-cache-key-#{entity_id}-#{key}"
  end

  def fetch_value_for_key(entity_id, key)
    prefixed_cache_key = get_prefixed_cache_key(entity_id, key)
    value_from_cache = Redis::Alfred.get(prefixed_cache_key)

    return value_from_cache if value_from_cache.present?

    '0000000000000'
  end
end
