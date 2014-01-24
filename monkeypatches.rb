puts "Monkey patching LDAP schema caches to activeldap. Expecting version 3.2.2"

require "active_ldap/adapter/base"

module ActiveLdap
  class Schema
    private
    def cache(key)
      $al_cache ||= {}
      ($al_cache[key] ||= [yield])[0]
    end
  end
end
