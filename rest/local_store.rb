require "redis"

module PuavoRest

# Writeable local store. Since ldap connection is read only on boot servers we
# need some simple store we can write to.. Here's simple Pstore wrapper.
module LocalStore

  module ClassMethods
    def local_store
      Thread.current[:redis_connection] ||= Redis.new CONFIG["redis"].symbolize_keys
    end
  end

  def local_store
    self.class.local_store
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  def self.close_connection
    if c = Thread.current[:redis_connection]
      c.quit
      Thread.current[:redis_connection] = nil
    end
  end

end
end
