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

  class LdapHashError < Exception; end

  class BadInput < LdapHashError
    def code
      400
    end
  end

  class NotFound < LdapHashError
    def code
      404
    end
  end

  class InternalError < LdapHashError
    def code
      500
    end
  end

  class BadCredentials < LdapHashError
    def code
      401
    end
  end

  # Configure ldap connection and orgation to Ldaphash
  # @param [Hash]
  # @option settings [Object] :connection LDAP connection object
  # @option settings [Object] :settings Organisation info
  def self.setup(settings)
    Thread.current[:ldap_hash_settings] =
      (Thread.current[:ldap_hash_settings] || {}).merge(settings)
  end

  # Clear current setup
  def self.clear_setup
    connection.unbind if connection?
    Thread.current[:ldap_hash_settings] = {}
  end

  # Temporally change settings
  #
  # @param [Hash] The temp settings
  # @param [Block] Temp settings will be in use during the block execution
  def self.with(temp_settings, &block)
    prev = Thread.current[:ldap_hash_settings]

    setup(prev.merge(temp_settings))
    val = block.call

    Thread.current[:ldap_hash_settings] = prev
    val
  end

  # Get current settings
  def self.settings
    Thread.current[:ldap_hash_settings]
  end

  # returns true if connection is configured
  def self.connection?
    settings && settings[:connection]
  end

  # returns true if organisation is configured
  def self.organisation?
    settings && settings[:organisation]
  end

  # Get current connection
  def self.connection
    if not connection?
      raise InternalError, "LDAP connection is not configured!"
    end
    settings[:connection]
  end

  # Get current organisation
  def self.organisation
    if not organisation?
      raise InternalError, "Organisation is not configured!"
    end
    settings[:organisation]
  end

end


# ldap attribute conversions
class LdapHash < Hash

  # Store for ldap attribute mappings
  @@ldap2json = {}

  # Define conversion between LDAP attribute and the JSON attribute
  #
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

  # @return [Array] LDAP attributes that will be converted
  def self.ldap_attrs
    @@ldap2json[self.name].keys
  end

  # Set Hash attribute with ldap attr conversion
  #
  # @param [String]
  # @param [any]
  def ldap_set(key, value)
      if ob = @@ldap2json[self.class.name][key.to_s]
        self[ob[:attr]] = ob[:convert].call(value)
      end
  end

  # Like normal Hash#merge! but convert attributes using the ldap mapping
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
    raise "ldap_base is not implemented for #{ self.name }"
  end

  # LDAP::LDAP_SCOPE_SUBTREE filter search for #ldap_base
  #
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
  # @see raw_filter
  def self.filter(*args)
    raw_filter(*args).map! do |entry|
      from_hash(entry)
    end
  end

  # Return all ldap entries from the current base
  #
  # @see ldap_base
  def self.all
    filter("(objectClass=*)")
  end

  # Find any ldap entry by dn
  #
  # @param dn [String]
  # @param attributes [Array of Strings]
  def self.by_dn(dn, attributes=nil)
    res = nil
    attributes ||= ldap_attrs

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
  callable_from_instance :escape
end
