require "redis"

module PuavoRest
# Random helpers
class LdapHash
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

  def self.is_dn(s)
    # Could be slightly better I think :)
    # but usernames should have no commas or equal signs
    s && s.include?(",") && s.include?("=")
  end

end

# Connection management
class LdapHash

  class LdapHashError < Exception; end


  KRB_LOCK = Mutex.new
  def self.sasl_bind(ticket)
    conn = LDAP::Conn.new(CONFIG["ldap"])
    conn.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    conn.sasl_quiet = true
    conn.start_tls
    KRB_LOCK.synchronize do
      begin
        kg = Krb5Gssapi.new(CONFIG["fqdn"], CONFIG["keytab"])
        kg.copy_ticket(ticket)
        username, org = kg.display_name.split("@")
        settings[:credentials][:username] = username
        LdapHash.setup(:organisation => Organisation.by_domain[org.downcase])
        conn.sasl_bind('', 'GSSAPI')
      rescue GSSAPI::GssApiError => err
        if err.message.match(/Clock skew too great/)
          raise KerberosError, :user => "Your clock is messed up"
        else
          raise KerberosError, :user => err.message
        end
      rescue Krb5Gssapi::NoDelegation => err
        raise KerberosError, :user =>
          "Credentials are not delegated! '--delegation always' missing?"
      ensure
        kg.clean_up
      end
    end
    conn
  end

  def self.dn_bind(dn, pw)
    conn = LDAP::Conn.new(CONFIG["ldap"])
    conn.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    conn.start_tls
    conn.bind(dn, pw)
    conn
  end

  def self.create_connection
    raise "Cannot create connection without credentials" if settings[:credentials].nil?
    credentials = settings[:credentials]
    conn = nil

    begin

      if credentials[:kerberos]
        conn = sasl_bind(credentials[:kerberos])
      else
        if credentials[:dn].nil?
          credentials[:dn] = LdapHash.setup(:credentials => CONFIG["server"]) do
            User.resolve_dn(credentials[:username])
          end
        end
        raise BadCredentials, "Bad username/dn or password" if not credentials[:dn]
        conn = dn_bind(credentials[:dn], credentials[:password])
      end

    rescue LDAP::ResultError
      raise BadCredentials, "Bad username/dn or password"
    end

    return conn
  end

  def self.settings
    Thread.current[:ldap_hash_settings] || { :credentials_cache => {} }
  end

  def self.settings=(settings)
    Thread.current[:ldap_hash_settings] = settings
  end

  def self.setup(opts, &block)
    prev = self.settings
    self.settings = prev.merge(opts)

    if opts[:credentials]
      self.settings[:credentials_cache] = {}
    end

    if block
      res = block.call
      self.settings = prev
    end
    res
  end

  def self.connection
    if conn = settings[:credentials_cache][:current_connection]
      return conn
    end
    if settings[:credentials]
      settings[:credentials_cache][:current_connection] = create_connection
    end
  end


  def self.organisation
    if settings[:organisation].nil?
      raise BadInput, :user => "Cannot configure organisation for this request"
    else
      settings[:organisation]
    end
  end

  def self.clear_setup
    self.settings = nil
  end

  def link(path)
    self.class.settings[:rest_root] + path
  end

end


# Class store implementation
class LdapHash

  # Store for ldap attribute mappings
  @@_class_store = {}
  def self._class_store
    @@_class_store[self] ||= {}
  end

  def self.class_store(name)
    define_method(name) do
      self.class._class_store[name] ||= {}
    end
    define_singleton_method(name) do
      _class_store[name] ||= {}
    end
  end

end

# ldap attribute conversions
class LdapHash
  class_store :pretty2ldap
  class_store :ldap2pretty
  class_store :converters
  attr_reader :ldap_attr_store

  def initialize(ldap_attr_store={})
    @ldap_attr_store = ldap_attr_store
    @cache = {}
  end


  # Define conversion between LDAP attribute and the JSON attribute
  #
  # @param ldap_name [Symbol] LDAP attribute to convert
  # @param pretty_name [Symbol] Value conversion block. Default: Get first array item
  # @param convert [Block] Use block to
  # @see convert
  def self.ldap_map(ldap_name, pretty_name, default_value=nil, &convert)
    pretty_name = pretty_name.to_sym
    ldap_name = ldap_name.to_sym
    pretty2ldap[pretty_name] = ldap_name
    ldap2pretty[ldap_name] = pretty_name

    converters[ldap_name] = {
      :default => default_value,
      :convert => convert
    }

    define_method pretty_name do
      get_original(pretty_name)
    end
  end


  def get_original(pretty_name)
    pretty_name = pretty_name.to_sym
    return @cache[pretty_name] if not @cache[pretty_name].nil?

    ldap_name = pretty2ldap[pretty_name]
    default_value = converters[ldap_name][:default]
    convert = converters[ldap_name][:convert]

    value = Array(@ldap_attr_store[ldap_name])

    # String values in our LDAP are always UTF-8
    value = value.map do |item|
      if item.respond_to?(:force_encoding)
        item.force_encoding("UTF-8")
      else
        item
      end
    end

    if Array(value).empty? && !default_value.nil?
      return default_value
    end

    if convert
      value = instance_exec(value, &convert)
    else
      value = Array(value).first
    end

    @cache[pretty_name] = value
  end

  def [](pretty_name)
    send(pretty_name.to_sym)
  end

  def []=(pretty_name, value)
    set(pretty_name, value)
  end

  def empty?
    @ldap_attr_store.empty?
  end

  # @return [Array] LDAP attributes that will be converted
  def self.ldap_attrs
    ldap2pretty.keys
  end

  # Set attribute using the original ldap attribute
  #
  # @param [String]
  # @param [any]
  def ldap_set(ldap_name, value)
    return if ldap2pretty[ldap_name.to_sym].nil?
    @ldap_attr_store[ldap_name.to_sym] = value
  end

  def set(pretty_name, value)
    @cache[pretty_name.to_sym] = value
  end

  # Like normal Hash#merge!
  def ldap_merge!(hash)
    hash.each do |ldap_name, value|
      ldap_set(ldap_name, value)
    end
    self
  end

  def merge(other)
    h = other.class == Hash ? other : other.ldap_attr_store
    new_h = @ldap_attr_store.dup
    h.each do |pretty_name, value|
      new_h[pretty2ldap[pretty_name.to_sym]] = value
    end
    self.class.new(new_h)
  end

  def to_hash
    h = {}
    pretty2ldap.each do |pretty_name, _|
      h[pretty_name.to_s] = send(pretty_name)
    end
    h
  end

  def to_ldap_hash
    @ldap_attr_store.dup
  end

  def as_json(*)
    to_hash
  end

  def to_json(*)
    as_json.to_json
  end

end


# generic ldap search rutines
class LdapHash

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
      attributes.map{ |a| a.to_s }
    ) do |entry|
      res.push(entry.to_hash) if entry.dn != ldap_base
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
  def self.raw_by_dn(dn, attributes=nil)
    res = nil
    attributes ||= ldap_attrs.map{ |a| a.to_s }

    connection.search(
      dn,
      LDAP::LDAP_SCOPE_SUBTREE,
      "(objectclass=*)",
      attributes
    ) do |entry|
      res = entry.to_hash
      break
    end

    res
  end

  # Return convert value to LdapHashes before returning
  # @see raw_by_dn
  def self.by_dn(*args)
    from_hash( raw_by_dn(*args) )
  end

end

# escaping helpers
class LdapHash
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
end
