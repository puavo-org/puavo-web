require "redis"

module PuavoRest

# Simple writeable local store mixin
#
# This mixins adds simple shortcuts for redis set and get. The class in which
# this mixin is included to must implemented a instance_key method which
# uniquely identifies the instance
module LocalStore

  module ClassMethods
    def local_store
      REDIS_CONNECTION
    end
  end

  def local_store
    self.class.local_store
  end

  def local_store_set(key, val)
    local_store.set("#{ instance_key }:#{ key }", val)
  end
  def local_store_get(key)
    local_store.get("#{ instance_key }:#{ key }")
  end
  def local_store_del(key)
    local_store.del("#{ instance_key }:#{ key }")
  end
  def local_store_expire(key, time)
    local_store.expire("#{ instance_key }:#{ key }", time)
  end


  def self.included(base)
    base.extend(ClassMethods)
  end

  # Close the Redis connection
  def self.close_connection
    if c = Thread.current[:redis_connection]
      c.quit
      Thread.current[:redis_connection] = nil
    end
  end

end
end
