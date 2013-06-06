# Random helpers
class LdapHash < Hash
  def self.callable_from_instance(method)
    klass = self
    define_method method do |*args|
      klass.send(method, *args)
    end
  end
end

# Connection management
class LdapHash < Hash

  def self.setup(settings)
    Thread.current[:ldap_hash_settings] = settings
  end

  def self.with(temp_settings, &block)
    prev = Thread.current[:ldap_hash_settings]

    setup(settings.merge(temp_settings))
    block.call

    Thread.current[:ldap_hash_settings] = prev
  end

  def self.settings
    Thread.current[:ldap_hash_settings]
  end
  callable_from_instance :settings

  def self.connection
    Thread.current[:ldap_hash_settings][:connection]
  end
  callable_from_instance :connection

  def self.organisation
    Thread.current[:ldap_hash_settings][:organisation]
  end
  callable_from_instance :organisation

end


# ldap attribute conversions
class LdapHash < Hash
  class UnknownLdapMap < Exception
  end

  @@ldap2json = {}
  # Define conversion between LDAP attribute and the JSON attribute
  # @param ldap_name [Symbol] LDAP attribute to convert
  # @param json_name [Symbol] Value conversion block. Default: Get first array item
  # @param convert [Block] Use block to
  # @see convert
  def self.ldap_map(ldap_name, json_name, &convert)
    hash = @@ldap2json[self.name] ||= {}
    hash[ldap_name.to_s] = {
      :attr => json_name.to_s,
      :convert => convert || lambda { |v| Array(v).first }
    }
  end

  # Return LDAP attributes that will be converted
  def self.ldap_attrs
    @@ldap2json[self.name].keys
  end

  def ldap_set(key, value)
      if ob = @@ldap2json[self.class.name][key.to_s]
        self[ob[:attr]] = ob[:convert].call(value)
      else
        raise UnknownLdapMap, key
      end
  end

  def ldap_merge!(hash)
    hash.each do |k,v|
      ldap_set(k,v)
    end
  end

end
