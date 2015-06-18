module PuavoRest

# Get unique and sequential IDs from Redis
class IdPool

  # Get range of Ids
  #
  # @param namespace [String] ID namespace. For example `puavoNextUidNumber` or `puavoNextGidNumber`
  # @param count [Fixnum] How many IDs should be returned
  # @return [Array<Fixnum>]
  def self.id_range(namespace, count)
    pool = get_redis_id_pool()

    if pool.get(namespace).nil?
      pool.set(namespace, 5000)
    end

    _id_range = (1..count).map do
      pool.incr(namespace)
    end

    return _id_range
  end

  # See what was the last given ID for the namespace
  #
  # @param namespace [String]
  # @return Fixnum
  def self.last_id(namespace)
    get_redis_id_pool.get(namespace)
  end

  # Get single id for ID the namespace
  #
  # @param namespace [String]
  # @return Fixnum
  def self.next_id(namespace)
    id_range(namespace, 1).first
  end

  # Set ID sequence to value. Using this can break things badly. Use with care!
  #
  # @param namespace [String]
  # @param value [Fixnum]
  def self.set_id!(namespace, value)
    pool = get_redis_id_pool()
    pool.set(namespace, value)
  end

  private

  def self.get_redis_id_pool
    Redis::Namespace.new(
      "idpool",
      :redis => REDIS_CONNECTION
    )
  end

end
end
