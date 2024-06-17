puts 'Monkey patching LDAP schema caching. Assuming the activeldap gem version is 7.0.0.'

# TODO: Is this file still needed?

# Because we do set the ldap connection manually for each request to the
# current users the defaul schema caching in ActiveLdap does not work because
# it gets reset when new connection is setup.
#
# Monkeypatch the cache to use global cache object which can be shared between
# multiple ldap connections
#
# XXX: This might not be thread safe. Currently it is not an issue because we
# deploy on Unicorn which is not multi threaded.
$active_ldap_schema_cache = {}
module ActiveLdap
  class Schema
    # https://github.com/activeldap/activeldap/blob/master/lib/active_ldap/schema.rb#L168-L171
    private
    def cache(key)
      ($active_ldap_schema_cache[key] ||= [yield])[0]
    end
  end

  module Configuration
    module ClassMethods
      def remove_configuration_by_key(key)
        @@defined_configurations.delete(key)
      end
    end
  end

  module Connection
    module ClassMethods
      # XXX Changed remove_configuration_by_configuration() call to pass key.
      # XXX This is probably wrong, why are connections in active_connections
      # XXX removed differently than connections defined_connections?
      def remove_connection(klass_or_key=self)
        if klass_or_key.is_a?(Module)
          key = active_connection_key(klass_or_key)
        else
          key = klass_or_key
        end
        config = configuration(key)
        conn = active_connections[key]
        remove_configuration_by_key(key)
        active_connections.delete_if {|_key, value| value == conn}
        conn.disconnect! if conn
        config
      end
    end
  end
end
