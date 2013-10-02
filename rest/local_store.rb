require "pstore"

module PuavoRest

# Writeable local store. Since ldap connection is read only on boot servers we
# need some simple store we can write to.. Here's simple Pstore wrapper.
module LocalStore

  module ClassMethods
    def local_store
      Redis.new :db => CONFIG["redis_db"]
    end
  end

  def local_store
    self.class.local_store
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

end

end
