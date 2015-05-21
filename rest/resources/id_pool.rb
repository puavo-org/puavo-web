module PuavoRest
class IdPool

  def self.id_range(id_field, count)
    pool = get_redis_id_pool()

    if pool.get(id_field).nil?
      pool.set(id_field, 5000)
    end

    _id_range = (1..count).map do
      pool.incr(id_field)
    end

    return _id_range
  end

  def self.last_id(id_field)
    get_redis_id_pool.get(id_field)
  end

  def self.next_id(id_field)
    id_range(id_field, 1).first
  end

  def self.set_id!(id_field, value)
    pool = get_redis_id_pool()
    pool.set(id_field, value)
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
