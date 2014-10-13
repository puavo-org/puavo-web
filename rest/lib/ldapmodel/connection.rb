
# Connection management
class LdapModel

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
        LdapModel.setup(:organisation => PuavoRest::Organisation.by_domain(org.downcase))
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

    if credentials[:dn].nil? && credentials[:kerberos].nil?
      raise BadCredentials, "Cannot connect - DN is missing!"
    end

    begin

      if credentials[:kerberos]
        conn = sasl_bind(credentials[:kerberos])
      else
        raise BadCredentials, "Bad username/dn or password" if not credentials[:dn]
        conn = dn_bind(credentials[:dn], credentials[:password])
      end

    rescue LDAP::ResultError => err
      if err.message == "Invalid credentials"
        raise BadCredentials, "Bad username/dn or password"
      else
        raise LdapError, err.message
      end
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


  def self.organisation?
    !!settings[:organisation]
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
