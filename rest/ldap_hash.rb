# Random helpers
class LdapHash < Hash
  def self.callable_from_instance(method)
    klass = self
    define_method method do |*args|
      klass.send(method, *args)
    end
  end

  # Create LdapHash from other hash. Converts attributes.
  def self.from_hash(hash)
    new.ldap_merge!(hash)
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
      end
  end

  def ldap_merge!(hash)
    hash.each do |k,v|
      ldap_set(k,v)
    end
    self
  end

end


# generic ldap search rutines
class LdapHash < Hash

  # LDAP base for this model. Must be implemented by subclasses
  def self.ldap_base
    raise "not implemented"
  end

  # LDAP::LDAP_SCOPE_SUBTREE filter search for #ldap_base
  # @param filter [String] LDAP filter
  # @param attributes [Array] Limit search results to these attributes
  # @see http://ruby-ldap.sourceforge.net/rdoc/classes/LDAP/Conn.html#M000025
  # @return [Array]
  def self.raw_filter(filter, attributes=nil)
    res = []
    attributes ||= ldap_attrs

    connection.search(
      ldap_base,
      LDAP::LDAP_SCOPE_SUBTREE,
      filter,
      attributes
    ) do |entry|
      res.push(entry.to_hash)
    end

    res
  end

  # Return convert values to LdapHashes before returning
  def self.filter(*args)
    raw_filter(*args).map! do |entry|
      from_hash(entry)
    end
  end

  # Find any ldap entry by dn
  #
  # @param dn [String]
  # @param attributes [Array of Strings]
  def by_dn(dn, attributes=[])
    res = nil

    connection.search(
      dn,
      LDAP::LDAP_SCOPE_SUBTREE,
      "(objectclass=*)",
      attributes
    ) do |entry|
      res = from_hash entry.to_hash
      break
    end

    res
  end

end

# escaping helpers
class LdapHash < Hash
  # http://tools.ietf.org/html/rfc4515 lists these exceptions from UTF1
  # charset for filters. All of the following must be escaped in any normal
  # string using a single backslash ('\') as escape.
  #
  ESCAPES = {
    "\0" => '00', # NUL            = %x00 ; null character
    '*'  => '2A', # ASTERISK       = %x2A ; asterisk ("*")
    '('  => '28', # LPARENS        = %x28 ; left parenthesis ("(")
    ')'  => '29', # RPARENS        = %x29 ; right parenthesis (")")
    '\\' => '5C', # ESC            = %x5C ; esc (or backslash) ("\")
  }
  # Compiled character class regexp using the keys from the above hash.
  ESCAPE_RE = Regexp.new(
    "[" +
    ESCAPES.keys.map { |e| Regexp.escape(e) }.join +
    "]"
  )

  # Escape unsafe user input for safe LDAP filter use
  #
  # @see https://github.com/ruby-ldap/ruby-net-ldap/blob/8ddb2d7c8476c3a2b2ad9fcd367ca0d36edaa611/lib/net/ldap/filter.rb#L247-L264
  def self.escape(string)
    string.gsub(ESCAPE_RE) { |char| "\\" + ESCAPES[char] }
  end
end
